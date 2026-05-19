-- ============================================================================
-- HARDENING ANON + PUBLIC EXECUTES — Befund NK3 (vollständiger Whitelist-Fix)
-- ============================================================================
--
-- Ausgangslage (Live-Audit 19.05.2026):
--   Die Rolle anon konnte ~30 csc_-Funktionen ausführen, obwohl der
--   öffentliche Flow (Bewerbungsbogen + Status-Seite + Dashboard-Pre-Auth)
--   final nur fünf davon braucht.
--   Ursache: PostgreSQL gibt SECURITY-DEFINER-Funktionen ohne expliziten
--   REVOKE automatisch EXECUTE-Recht an PUBLIC. anon erbt das über PUBLIC.
--
-- Warum hier KEIN Nachgranten für authenticated nötig ist:
--   Die Live-Inspektion (information_schema.role_routine_grants) zeigt: jede
--   csc_-Funktion hat ein EIGENES, explizites EXECUTE-Recht für die Rolle
--   authenticated — zusätzlich zum PUBLIC-Default. Der REVOKE FROM PUBLIC
--   trifft authenticated also NICHT; das Dashboard bleibt voll funktionsfähig.
--   Damit entfällt der heikle Teil des ursprünglichen Plans (authenticated-
--   Whitelist nachpflegen, sonst klemmt das Dashboard).
--
-- ⚠ WARNUNG — `REVOKE … FROM PUBLIC` trifft ALLE Rollen, nicht nur anon ⚠
--   Wenn eine Funktion EXECUTE nur über den PUBLIC-Default hatte (kein
--   explizites GRANT TO <rolle>), verliert nach diesem Patch JEDE Rolle den
--   Zugriff — inkl. anon, service_role, authenticated und postgres.
--
--   BESONDERS UNTERSCHÄTZT: Aufruf-Ketten über Rollen-Grenzen hinweg. Eine
--   Edge Function mit service_role-Key kann intern eine SECURITY-INVOKER-
--   Funktion (oder eine SECURITY-DEFINER-Funktion einer Funktion …) anstoßen,
--   die ihrerseits eine Helper-Funktion im anon-Kontext aufruft. Wenn EINE
--   dieser Funktionen ihr EXECUTE nur über PUBLIC hatte, bricht die ganze
--   Kette — und der Fehler taucht *in der Edge Function* auf, scheinbar
--   unabhängig vom Patch.
--
--   Reale Beispiele aus dem Live-Test (19.05.2026):
--     - Dashboard-Login brach mit "permission denied for function
--       csc_check_login_allowed" — pre-auth als anon, fehlendes anon-GRANT.
--     - Edge Function `get-bewerbung-status` (Service-Role) brach mit
--       "non-2xx status code". Ursache: in der Aufrufkette landete
--       csc_check_email_whitelist im anon-Kontext und hatte kein anon-Grant
--       (nur authenticated/postgres/service_role per Live-Abfrage bestätigt).
--       Fix: explizites GRANT TO anon (siehe Abschnitt 3).
--
--   Lehre: NACH JEDEM PUBLIC-REVOKE end-to-end testen — mindestens:
--     1. Bewerbungsbogen absenden + Anhang hochladen      (anon)
--     2. Status-Seite öffnen + Vertragsdaten speichern    (anon + Edge Function!)
--     3. Bewerbung zurückziehen                            (Edge Function!)
--     4. Dashboard-Login                                   (pre-auth anon)
--     5. Dashboard Bewerbung öffnen, Notiz/Tag setzen      (authenticated)
--     6. Personal-Soll / Stammdaten speichern              (authenticated RPC)
--     7. Status-Mails durch Status-Wechsel auslösen        (Edge Function!)
--   Wenn eine Edge Function fehlschlägt, NICHT pauschal an service_role
--   granten — die SQL-Fehlermeldung nennt den genauen Funktionsnamen UND
--   die Rolle, in der die Funktion gerufen wird (oft anon, weil die Kette
--   bei einem SECURITY-INVOKER-Schritt in den Caller-Kontext zurückfällt).
--   Gezielt nachgranten, nicht pauschal.
--
-- Bereits per hardening_anon_grants_2.sql gesperrt (NK3 Sofort-Teil):
--   csc_auto_assign_hauptverein_admin, csc_auto_promote_admin,
--   csc_cleanup_old_bewerbungen, csc_cleanup_error_log
--   (Ergänzung: beide auto_*-Funktionen sind RETURNS-trigger an auth.users
--    und prüfen die E-Mail intern gegen eine Whitelist — kein Self-Promotion-
--    Loch. Der REVOKE schadet trotzdem nicht, weil Trigger unter Owner-Kontext
--    feuern.)
--
-- Quelle der anon-Whitelist (5 Funktionen):
--   Direkte .rpc()-Aufrufe:
--     csc-bewerbungen/index.html         → keine RPCs
--     csc-bewerbungen/status/index.html  → get_vertragsdaten_status,
--                                          save_vertragsdaten
--     csc-bewerbungen/dashboard/index.html:2001 (pre-auth, anon-Kontext)
--                                        → csc_check_login_allowed
--   Plus implizit:
--     csc_bewerbung_exists(uuid) — WITH CHECK der INSERT-Policy
--                                  csc_anhaenge_insert_public (Anhang-Upload)
--     csc_check_email_whitelist() — wird in der Aufruf-Kette der
--                                  Edge Function get-bewerbung-status im
--                                  anon-Kontext erreicht. Signatur ist
--                                  PARAMETERLOS (am 19.05.2026 live geprüft).
--
-- Verifikation NACH dem Lauf (im SQL-Editor):
--   SELECT routine_name, privilege_type
--   FROM   information_schema.role_routine_grants
--   WHERE  grantee = 'anon' AND specific_schema = 'public'
--   ORDER  BY routine_name;
--   -- Erwartet: NUR
--   --   csc_bewerbung_exists      EXECUTE
--   --   csc_check_email_whitelist EXECUTE
--   --   csc_check_login_allowed   EXECUTE
--   --   get_vertragsdaten_status  EXECUTE
--   --   save_vertragsdaten        EXECUTE
-- ============================================================================


-- ── (1) Bestand aufräumen ──────────────────────────────────────────────────
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;


-- ── (2) Defaults für künftige Funktionen schließen ────────────────────────
-- authenticated NICHT in der Default-Klausel anfassen — sonst gehen künftige
-- explizite GRANTs aus feature_*-Migrationen verloren bzw. müssen jedes Mal
-- nachgezogen werden.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;


-- ── (3) anon-Whitelist gezielt zurückgeben ─────────────────────────────────
GRANT EXECUTE ON FUNCTION csc_bewerbung_exists(uuid)        TO anon;
GRANT EXECUTE ON FUNCTION get_vertragsdaten_status(text)    TO anon;
GRANT EXECUTE ON FUNCTION save_vertragsdaten(text, jsonb)   TO anon;

-- csc_check_login_allowed: pre-auth Anti-Spam-Check für den Dashboard-Login.
-- Wird aus dashboard/index.html:2001 VOR `sb.auth.signInWithOtp` aufgerufen,
-- läuft also zwangsläufig im anon-Kontext (der User ist zu diesem Zeitpunkt
-- noch nicht authentifiziert). Ohne dieses GRANT bricht der Dashboard-Login
-- mit "permission denied for function csc_check_login_allowed" — im Live-Test
-- am 19.05.2026 genau so passiert.
--
-- Restrisiko (bewusst akzeptiert): Mit anon-EXECUTE wirkt die Funktion als
-- Oracle — jeder mit dem Anon-Key kann durchprobieren, welche Adressen
-- freigeschaltet sind. Vereinsvorstands-Mails stehen aber ohnehin im
-- Impressum jedes Vereins, daher kein neuer Leak. Folge-Umbau-Option: den
-- Whitelist-Check hinter den Magic-Link-Callback verlegen (= authenticated),
-- dann kann dieses GRANT raus. Bis dahin ist es Pflicht.
GRANT EXECUTE ON FUNCTION csc_check_login_allowed(text)     TO anon;

-- csc_check_email_whitelist: indirekt nötig für die Edge Function
-- `get-bewerbung-status` (Status-Seite öffnen). Die Edge Function läuft mit
-- service_role, ruft aber in ihrer internen Aufruf-Kette eine Funktion, die
-- ihrerseits csc_check_email_whitelist im anon-Kontext anstößt. Ohne dieses
-- GRANT antwortet die Function mit "non-2xx status code" und die Status-
-- Seite zeigt "Bewerbung nicht gefunden" — im Live-Test am 19.05.2026
-- genau so passiert. Live-Grants-Abfrage hat bestätigt: csc_check_email_-
-- whitelist hatte EXECUTE für authenticated, postgres und service_role,
-- ABER NICHT für anon — der PUBLIC-Revoke war der Auslöser.
--
-- Hinweis zur sauberen Lösung: Den Source der Edge Function get-bewerbung-
-- status ins Repo holen (liegt heute nicht vor — siehe OFFENE_PUNKTE.md),
-- die Aufruf-Kette identifizieren und die ungewollte anon-Kontext-Vermittlung
-- entweder per SECURITY DEFINER abdichten oder service_role explizit
-- mitnehmen. Dann kann dieses anon-GRANT wieder raus.
-- Signatur: parameterlos (per pg_get_function_identity_arguments am
-- 19.05.2026 bestätigt — der vorherige Versuch mit (text) schlug fehl).
GRANT EXECUTE ON FUNCTION csc_check_email_whitelist()       TO anon;
-- ============================================================================

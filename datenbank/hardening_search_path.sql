-- ============================================================================
-- HARDENING SEARCH_PATH — Befund NK2
-- ============================================================================
--
-- Ausgangslage (Live-Audit 19.05.2026, Block 6):
--   11 SECURITY-DEFINER-Funktionen hatten `proconfig = null`, also kein
--   gepinntes search_path. Bei SECURITY DEFINER ist das ein klassischer
--   Privilege-Escalation-Vektor: wer in einem früher im search_path
--   liegenden Schema CREATE-Rechte hat, kann Tabellen-/Operator-Auflösung
--   in der Function umlenken. Supabase-Linter meldet das als
--   `function_search_path_mutable`.
--
-- Inventur — wo die 11 Funktionen definiert sind:
--   10 Funktionen leben ausschließlich in der Live-DB
--      (kein CREATE FUNCTION im Repo) → reines ALTER FUNCTION, siehe unten.
--    1 Funktion ist im Repo definiert:
--      csc_withdraw_bewerbung(text) in datenbank/fix_withdraw_bewerbung.sql:103
--      → wurde am 19.05.2026 zusätzlich in der Quelldatei mit
--        `SET search_path = public` ergänzt (sonst kommt der Defekt beim
--        nächsten Re-Run der Datei zurück). Der ALTER hier setzt das gleiche
--        Recht in der Live-DB.
--
-- Signatur-Verifikation:
--   Alle 11 Signaturen wurden am 19.05.2026 per
--   pg_get_function_identity_arguments live gegengeprüft. Acht Funktionen
--   sind parameterlos, drei haben Parameter (csc_check_login_allowed(text),
--   csc_compute_bewerbung_score(uuid), csc_withdraw_bewerbung(text)). Die
--   ALTER-Statements unten bilden diese Signaturen 1:1 ab — keine
--   Schätzungen, keine Platzhalter.
--
--   Lehre aus dieser Session: in zwei Stunden sind zweimal GRANT-Statements
--   mit geratenen Signaturen gescheitert (csc_check_email_whitelist(text)
--   statt parameterlos; Vertragsdaten-GRANTs zwischendurch). Für künftige
--   Patches an Funktionen IMMER vor dem Schreiben dieses Statements
--   ausführen:
--     SELECT proname, pg_get_function_identity_arguments(oid)
--     FROM pg_proc
--     WHERE proname = '<name>';
-- ============================================================================


BEGIN;


-- ── ALTER FUNCTION für alle 11 Funktionen ──────────────────────────────────
ALTER FUNCTION public.csc_auto_promote_admin()          SET search_path = public;
ALTER FUNCTION public.csc_check_email_whitelist()       SET search_path = public;
ALTER FUNCTION public.csc_check_login_allowed(text)     SET search_path = public;
ALTER FUNCTION public.csc_cleanup_old_bewerbungen()     SET search_path = public;
ALTER FUNCTION public.csc_compute_bewerbung_score(uuid) SET search_path = public;
ALTER FUNCTION public.csc_current_user_rolle()          SET search_path = public;
ALTER FUNCTION public.csc_current_user_verein()         SET search_path = public;
ALTER FUNCTION public.csc_is_hauptverein()              SET search_path = public;
ALTER FUNCTION public.csc_is_hauptverein_admin()        SET search_path = public;
ALTER FUNCTION public.csc_trigger_compute_score()       SET search_path = public;
ALTER FUNCTION public.csc_withdraw_bewerbung(text)      SET search_path = public;


-- ── VERIFIKATION (vor COMMIT) ──────────────────────────────────────────────
-- Jede der 11 Funktionen sollte jetzt proconfig = {search_path=public} haben:
SELECT p.proname,
       p.prosecdef                                  AS security_definer,
       p.proconfig                                  AS config,
       pg_get_function_identity_arguments(p.oid)    AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'csc_auto_promote_admin', 'csc_check_email_whitelist',
    'csc_check_login_allowed', 'csc_cleanup_old_bewerbungen',
    'csc_compute_bewerbung_score', 'csc_current_user_rolle',
    'csc_current_user_verein', 'csc_is_hauptverein',
    'csc_is_hauptverein_admin', 'csc_trigger_compute_score',
    'csc_withdraw_bewerbung'
  )
ORDER BY p.proname;
-- Erwartet: 11 Zeilen, jede mit config = {search_path=public}.
-- Wenn eine Zeile fehlt oder config NULL ist → ROLLBACK, prüfen, neu.


COMMIT;
-- Bei unerwartetem Ergebnis stattdessen:
--   ROLLBACK;
--
-- Nach erfolgreichem COMMIT zusätzlich Smoketest analog zu
-- hardening_anon_executes.sql (Bewerbungsbogen, Status-Seite, Dashboard-Login,
-- Status-Mails) — search_path-Änderungen sollten zwar funktional unsichtbar
-- sein, aber wenn eine Funktion bisher implizit auf ein anderes Schema im
-- Pfad zugriff (z. B. auth), würde sich das jetzt bemerkbar machen.
-- Funktionen mit search_path = "public, auth" in Block 6
-- (csc_link_auth_user_to_dashboard, csc_user_*, csc_track_*) sind nicht Teil
-- dieses Patches — die sind schon korrekt gepinnt.
-- ============================================================================

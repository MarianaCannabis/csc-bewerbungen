-- ============================================================================
-- HARDENING ANON GRANTS — Teil 2 (Nachzügler aus Live-Audit)
-- ============================================================================
--
-- Befund NK1 aus dem Sicherheits-Review (18.05.2026):
-- Die erste Hardening-Migration (hardening_anon_grants.sql, 15.05.2026) hat
-- nur 7 csc_-Tabellen abgedeckt. Bei einer Live-Verifikation der anon-
-- Tabellen-GRANTs zeigte sich, dass mehrere weitere sensible Tabellen noch
-- die Default-Privilegien (DELETE / INSERT / REFERENCES / SELECT / TRIGGER /
-- TRUNCATE / UPDATE) für die Rolle anon haben.
--
-- Warum das kritisch ist:
--   - TRUNCATE umgeht RLS in PostgreSQL vollständig. Wer den anon-Key kennt
--     (steht im Frontend-Code, also öffentlich), kann mit einem einzigen
--     HTTP-Call die Tabelleninhalte komplett leeren.
--   - Besonders heikel:
--       csc_vertragsdaten              — sensible Vertrags-/Lohndaten (Art. 9 DSGVO-Risiko)
--       csc_hauptverein_admin_whitelist — Login-Whitelist; leer = alle Admins ausgesperrt
--       csc_error_log / csc_mail_log    — Audit-Spuren; leer = forensische Lücke
--       csc_bewerbung_status_log        — Status-Historie der Bewerbungen
--
-- Diese Datei dient nur der Dokumentation und Versionierung — ausgeführt
-- wird sie im Supabase-SQL-Editor. Die Statements sind idempotent.
--
-- Verifikation NACH dem Lauf (im SQL-Editor):
--   SELECT table_name, privilege_type
--   FROM information_schema.role_table_grants
--   WHERE grantee = 'anon' AND table_name LIKE 'csc_%'
--   ORDER BY table_name;
--   -- Erwartet: NUR noch csc_bewerbung_anhaenge INSERT, csc_bewerbungen
--   --          INSERT, csc_vereine SELECT (plus evtl. csc_vereine_public /
--   --          csc_projects falls die fachlich anon-erreichbar bleiben sollen).
-- ============================================================================

REVOKE ALL ON TABLE csc_vertragsdaten              FROM anon;
REVOKE ALL ON TABLE csc_hauptverein_admin_whitelist FROM anon;
REVOKE ALL ON TABLE csc_bewerbung_status_log       FROM anon;
REVOKE ALL ON TABLE csc_error_log                  FROM anon;
REVOKE ALL ON TABLE csc_mail_log                   FROM anon;

-- ── NK1 Teil 2 ─────────────────────────────────────────────────────────────
-- Drei weitere Objekte aus dem Live-Audit:
--   csc_projects                 — interne Tabelle, anon braucht keinen Zugriff
--   csc_bewerbungen_uebersicht   — Dashboard-View; KEIN öffentlicher Zugriff
--   csc_vereine_public           — Vereins-Auswahl im Bewerbungsbogen;
--                                  Spalten id, name, ort, plz, kurzname
--                                  → unkritisch, anon braucht SELECT zurück
REVOKE ALL    ON TABLE csc_projects               FROM anon;
REVOKE ALL    ON TABLE csc_bewerbungen_uebersicht FROM anon;
REVOKE ALL    ON TABLE csc_vereine_public         FROM anon;
GRANT  SELECT ON TABLE csc_vereine_public         TO   anon;

-- ── NK3 Sofort-Teil ────────────────────────────────────────────────────────
-- Befund NK3 (19.05.2026): anon hatte EXECUTE auf ~30 Funktionen, weil das
-- EXECUTE-Recht sowohl an anon als auch an PUBLIC als auch an authenticated
-- hing (Postgres-Default für SECURITY-DEFINER-Funktionen ohne expliziten
-- REVOKE). Ein `REVOKE … FROM anon` allein wirkt deshalb nicht — die Rolle
-- erbt das Recht weiter über PUBLIC. Daher zwingend `FROM anon, PUBLIC`.
--
-- Diese vier Funktionen sind die akutesten Kandidaten:
--   csc_auto_assign_hauptverein_admin — Name suggeriert Privilege-Vergabe;
--                                       Definition nicht im Repo verifizierbar
--   csc_auto_promote_admin            — dito
--   csc_cleanup_old_bewerbungen       — Mass-DELETE (6-Monats-Bereinigung);
--                                       läuft als Cron unter Owner-Rolle weiter
--   csc_cleanup_error_log             — Audit-Trail-Wegwischen
--
-- Keine dieser vier wird vom öffentlichen Code aufgerufen — gefahrlos.
-- Vollständiger NK3-Whitelist-Ansatz folgt in einer separaten Migration
-- (REVOKE ALL FROM anon, PUBLIC + gezielte GRANTs für die 4 anon-Funktionen).
REVOKE EXECUTE ON FUNCTION csc_auto_assign_hauptverein_admin() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION csc_auto_promote_admin()            FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION csc_cleanup_old_bewerbungen()       FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION csc_cleanup_error_log()             FROM anon, PUBLIC;

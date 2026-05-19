-- ============================================================================
-- MIGRATION-LOG: Audit-Trail aller Schema-/Policy-Änderungen
-- ============================================================================
-- 
-- Zweck: Nachvollziehbar machen wer wann welche Migration ausgeführt hat.
-- Hilft später bei "wann wurde X gefixt?"-Fragen und ist DSGVO-relevant 
-- (Rechenschaftspflicht Art. 5(2) — Nachweis dass technische Maßnahmen 
-- ergriffen wurden).
--
-- Workflow für ZUKÜNFTIGE Migrationen:
--   1. SQL-Script ausführen
--   2. Am Ende:
--        INSERT INTO csc_migration_log (migration_id, beschreibung, autor)
--        VALUES ('YYYY-MM-DD_kurzname', 'Was wurde geändert', auth.email());
-- ============================================================================

-- ── Tabelle anlegen (idempotent) ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS csc_migration_log (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  migration_id    TEXT        NOT NULL UNIQUE,
  beschreibung    TEXT        NOT NULL,
  ausgefuehrt_am  TIMESTAMPTZ NOT NULL DEFAULT now(),
  autor           TEXT,                          -- E-Mail des Ausführenden
  notizen         TEXT,                          -- Optional: zusätzliche Doku
  CONSTRAINT csc_migration_log_id_format 
    CHECK (migration_id ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[a-z0-9_]+$')
);

COMMENT ON TABLE  csc_migration_log IS 'Audit-Trail aller Schema- und Policy-Änderungen am CSC-Bewerbungssystem';
COMMENT ON COLUMN csc_migration_log.migration_id   IS 'Format: YYYY-MM-DD_kurzname (eindeutig)';
COMMENT ON COLUMN csc_migration_log.beschreibung   IS 'Was wurde geändert und warum';
COMMENT ON COLUMN csc_migration_log.ausgefuehrt_am IS 'Wann das Script ausgeführt wurde';
COMMENT ON COLUMN csc_migration_log.autor          IS 'E-Mail-Adresse des Ausführenden';
COMMENT ON COLUMN csc_migration_log.notizen        IS 'Optionale zusätzliche Doku (z.B. betroffene Tabellen)';


-- ── RLS aktivieren — nur Hauptverein-Admins dürfen sehen ──────────────────
ALTER TABLE csc_migration_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS csc_migration_log_select_admin ON csc_migration_log;
CREATE POLICY csc_migration_log_select_admin
  ON csc_migration_log
  FOR SELECT
  TO authenticated
  USING (csc_is_hauptverein_admin());

-- Nur das Postgres-DB-Owner kann INSERTs machen (über SQL-Editor mit
-- service_role). authenticated/anon sollen NICHT direkt schreiben können.
REVOKE ALL ON TABLE csc_migration_log FROM anon, authenticated;
GRANT  SELECT ON TABLE csc_migration_log TO authenticated;


-- ── Rückwirkende Einträge: alles was wir heute (15.05.2026) gemacht haben ─
-- ON CONFLICT: idempotent, kann mehrmals laufen ohne Doppelung

INSERT INTO csc_migration_log (migration_id, beschreibung, ausgefuehrt_am, autor, notizen)
VALUES
  (
    '2026-05-15_fix_withdraw_bewerbung',
    'Bug 1: DSGVO-Selbstlöschung repariert. Alte SQL-Function csc_withdraw_bewerbung() konnte storage.objects nicht mehr direkt löschen (Supabase-Plattform-Änderung). Neue Edge Function "withdraw-bewerbung" + neue SQL-Function csc_withdraw_bewerbung_db_only(uuid). Alte Function als Deprecated-Stub erhalten.',
    '2026-05-15 22:00:00+02',
    'andre.reiche@mariana-cannabis.de',
    'Betroffen: storage/bewerbung-anhaenge bucket, csc_withdraw_bewerbung, csc_withdraw_bewerbung_db_only, Edge Function withdraw-bewerbung, status_index.html Build 2026-05-15T2230'
  ),
  (
    '2026-05-15_dashboard_client_filter',
    'Bug 2a: Client-seitiger Filter in loadBewerbungen() ergänzt — Defense in Depth gegen RLS-Race-Conditions beim Initial-Load. Vorher: nur Polling filterte, Initial-Load verließ sich auf RLS allein. Notiz-Counts mit .in(ids) eingeschränkt statt SELECT *.',
    '2026-05-15 22:15:00+02',
    'andre.reiche@mariana-cannabis.de',
    'Betroffen: dashboard.html Build 2026-05-15T2230, Funktionen loadBewerbungen + silentReloadBewerbungen'
  ),
  (
    '2026-05-15_drop_select_self_token_leak',
    'KRITISCH: RLS-Policy "csc_bewerbungen_select_self_token" gedroppt. Diese ließ {anon, authenticated} alle Bewerbungen sehen wenn bewerber_token IS NOT NULL — also faktisch alle Bewerbungen. Massiver DSGVO-Verstoß. Status-Seite läuft jetzt komplett über Edge Function get-bewerbung-status mit Service-Role. Zusätzlich: 4 weitere Policies von {public} auf {authenticated} gehärtet.',
    '2026-05-15 22:30:00+02',
    'andre.reiche@mariana-cannabis.de',
    'Betroffen: csc_bewerbungen alle Policies, status_index.html Build 2026-05-15T2245'
  ),
  (
    '2026-05-15_hardening_anon_grants',
    'Defense-in-Depth-Hardening: (a) csc_anhaenge_insert_public hat jetzt with_check (csc_bewerbung_exists(bewerbung_id)) — anon kann keine Anhänge zu nicht-existierenden Bewerbungen mehr einfügen. (b) anon Tabellen-GRANTs auf das absolute Minimum reduziert (INSERT auf csc_bewerbungen + csc_bewerbung_anhaenge, SELECT auf csc_vereine, sonst nichts).',
    '2026-05-15 22:45:00+02',
    'andre.reiche@mariana-cannabis.de',
    'Betroffen: csc_bewerbung_exists (neue Function), csc_anhaenge_insert_public, anon-GRANTs auf 7 csc_-Tabellen'
  )
ON CONFLICT (migration_id) DO NOTHING;


-- ── Verifikation ──────────────────────────────────────────────────────────
SELECT 
  migration_id, 
  ausgefuehrt_am, 
  autor,
  left(beschreibung, 80) || '…' AS beschreibung_kurz
FROM csc_migration_log
ORDER BY ausgefuehrt_am DESC;

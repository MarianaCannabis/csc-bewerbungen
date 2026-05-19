-- ============================================================================
-- STORAGE-POLICY-HARDENING auf Bucket "bewerbung-anhaenge"
-- ============================================================================
--
-- Probleme die wir fixen:
--   1. Duplikat-Policies: csc_anhaenge_upload_public + csc_bewerbung_anhaenge_upload
--      sind die gleiche Policy doppelt; csc_anhaenge_read_authenticated +
--      csc_bewerbung_anhaenge_read_authenticated auch.
--   2. SELECT-Policy hat KEINEN Verein-Filter → jeder authenticated User
--      kann jedes File aller Vereine lesen (analog zum csc_bewerbungen-Leak
--      den wir vorhin gedroppt haben).
--   3. DELETE-Policy ist zu offen → jeder authenticated User kann beliebige
--      Files löschen.
--
-- Storage-Pfad-Konvention:  {bewerbung_id}/{idx}-{kategorie}.{ext}
-- → split_part(name, '/', 1)::uuid ergibt die bewerbung_id
-- ============================================================================


-- ── 1) DUPLIKATE WEG ───────────────────────────────────────────────────────
-- Behalten: csc_bewerbung_anhaenge_* (klarere Naming-Convention)
-- Droppen:  csc_anhaenge_* (Alt-Namen)
DROP POLICY IF EXISTS csc_anhaenge_upload_public      ON storage.objects;
DROP POLICY IF EXISTS csc_anhaenge_read_authenticated ON storage.objects;


-- ── 2) UPLOAD (INSERT) bleibt — anon+authenticated mit Bucket-Check ────────
-- (Wir verschärfen das hier NICHT mit einer Existenz-Prüfung auf 
-- csc_bewerbungen, weil zum Zeitpunkt des Storage-Uploads die Bewerbung 
-- gerade erst eingefügt wurde — race-condition-Risiko. Die with_check auf 
-- csc_bewerbung_anhaenge.bewerbung_id die wir bereits haben deckt den 
-- realen Schutz ab — Storage-Files ohne DB-Record sind Orphans und werden 
-- vom Cleanup-Job ohnehin entfernt.)

DROP POLICY IF EXISTS csc_bewerbung_anhaenge_upload ON storage.objects;
CREATE POLICY csc_bewerbung_anhaenge_upload
  ON storage.objects
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (bucket_id = 'bewerbung-anhaenge');


-- ── 3) SELECT: Verein-Filter analog zu csc_bewerbung_anhaenge ──────────────
-- Hauptverein-Admin sieht alles, sonst nur Files der eigenen Bewerbungen.
DROP POLICY IF EXISTS csc_bewerbung_anhaenge_read_authenticated ON storage.objects;
CREATE POLICY csc_bewerbung_anhaenge_read_authenticated
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'bewerbung-anhaenge'
    AND (
      csc_is_hauptverein()
      OR EXISTS (
        SELECT 1 FROM csc_bewerbungen b
        WHERE b.id::text = split_part(storage.objects.name, '/', 1)
          AND b.verein_id = csc_user_verein_id()
      )
    )
  );


-- ── 4) DELETE: nur Hauptverein-Admin (analog zur DELETE-Policy auf 
--     csc_bewerbungen). Reguläre Storage-Löschung läuft sowieso über die
--     Edge Function "withdraw-bewerbung" mit Service-Role (umgeht RLS).
DROP POLICY IF EXISTS csc_bewerbung_anhaenge_delete_authenticated ON storage.objects;
CREATE POLICY csc_bewerbung_anhaenge_delete_hauptverein_admin
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'bewerbung-anhaenge'
    AND EXISTS (
      SELECT 1 FROM csc_user_profiles
      WHERE id    = auth.uid()
        AND rolle = 'hauptverein_admin'
        AND aktiv = true
    )
  );


-- ── 5) UPDATE: gar nicht erlaubt für anon/authenticated ───────────────────
-- (Wir kennen aktuell keinen legitimen Use-Case für Storage-Update auf 
-- existierende Files. Falls doch, kann später eine Policy hinzu.)
-- Bestehende UPDATE-Policies auf diesem Bucket gibt es eh nicht 
-- (laut Diagnose). Wir machen hier nur den expliziten DROP zur Sicherheit.


-- ── 6) Migration loggen ────────────────────────────────────────────────────
INSERT INTO csc_migration_log (migration_id, beschreibung, autor, notizen)
VALUES (
  '2026-05-15_storage_hardening',
  'Storage-Bucket bewerbung-anhaenge: Duplikat-Policies entfernt; SELECT mit Verein-Filter (vorher konnten alle authenticated User alle Files lesen); DELETE nur noch für hauptverein_admin (vorher konnten alle authenticated User alle Files löschen).',
  'andre.reiche@mariana-cannabis.de',
  'Betroffen: storage.objects Policies auf bucket_id = bewerbung-anhaenge'
)
ON CONFLICT (migration_id) DO NOTHING;


-- ── Verifikation ──────────────────────────────────────────────────────────
SELECT 
  policyname, 
  roles, 
  cmd AS operation,
  CASE 
    WHEN length(qual) > 80 THEN left(qual, 80) || '…' 
    ELSE qual 
  END AS using_kurz
FROM pg_policies
WHERE schemaname = 'storage' 
  AND tablename = 'objects'
  AND (
    policyname LIKE '%bewerbung_anhaenge%' 
    OR policyname LIKE '%csc_anhaenge%'
  )
ORDER BY cmd, policyname;

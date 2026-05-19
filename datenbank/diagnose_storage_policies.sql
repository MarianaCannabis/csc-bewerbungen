-- ============================================================================
-- DIAGNOSE: Storage-Bucket-Policies auf "bewerbung-anhaenge"
-- ============================================================================
-- 
-- Hintergrund: Die DSGVO-Selbstlöschung läuft inzwischen über Edge Function 
-- mit Service-Role. Aber: Bewerber laden ANHÄNGE beim Absenden mit anon-Key 
-- direkt in den Bucket hoch. Wir müssen prüfen ob anon nur UPLOAD darf — 
-- und KEINEN LESE-Zugriff auf Files anderer Bewerbungen hat.
-- 
-- Typische Schwachstellen:
--   - anon kann beliebige Files lesen (z.B. "SELECT bucket_id, ..." auf storage.objects)
--   - anon kann Pfade enumerieren via list()
--   - anon kann fremde Files überschreiben oder löschen
--   - public Bucket statt private
-- ============================================================================


-- ── 1) Bucket-Existenz und Public/Private-Status ──────────────────────────
SELECT 
  id              AS bucket_id,
  name,
  public          AS ist_oeffentlich,  -- DARF NICHT true sein!
  file_size_limit,
  allowed_mime_types,
  created_at,
  updated_at
FROM storage.buckets
WHERE id = 'bewerbung-anhaenge';


-- ── 2) Alle Policies auf storage.objects (Bucket-Level-Berechtigungen) ───
SELECT 
  policyname,
  roles,
  cmd AS operation,
  qual AS using_expression,
  with_check AS with_check_expression
FROM pg_policies
WHERE schemaname = 'storage' 
  AND tablename = 'objects'
ORDER BY cmd, policyname;


-- ── 3) GRANTs auf storage.objects (sollten primary über RLS laufen) ──────
SELECT 
  grantee, 
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'storage' 
  AND table_name = 'objects'
ORDER BY grantee, privilege_type;


-- ── 4) Anzahl tatsächlicher Files im Bucket (Größenordnung) ──────────────
SELECT 
  count(*)                          AS anzahl_files,
  pg_size_pretty(sum(coalesce(metadata->>'size', '0')::bigint)) AS gesamt_groesse,
  count(DISTINCT split_part(name, '/', 1))  AS anzahl_bewerbungen_mit_files
FROM storage.objects
WHERE bucket_id = 'bewerbung-anhaenge';


-- ── 5) Orphan-Check: Storage-Files OHNE entsprechenden DB-Eintrag in
-- csc_bewerbung_anhaenge (z.B. weil DSGVO-Löschung Storage-Files vergessen 
-- hat — sollte nach unserem Fix nicht mehr passieren, aber gut zu sehen)
WITH storage_files AS (
  SELECT 
    name                                AS file_path,
    split_part(name, '/', 1)::uuid      AS bewerbung_id_aus_pfad
  FROM storage.objects
  WHERE bucket_id = 'bewerbung-anhaenge'
)
SELECT 
  count(*)                              AS orphan_files
FROM storage_files sf
LEFT JOIN csc_bewerbung_anhaenge a ON a.storage_path = sf.file_path
WHERE a.id IS NULL;


-- ── 6) Reverse-Orphan-Check: DB-Einträge OHNE Storage-File
SELECT 
  count(*)                              AS db_orphans
FROM csc_bewerbung_anhaenge a
LEFT JOIN storage.objects o 
  ON o.bucket_id = 'bewerbung-anhaenge' AND o.name = a.storage_path
WHERE a.storage_path IS NOT NULL
  AND o.id IS NULL;

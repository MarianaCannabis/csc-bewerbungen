-- ============================================================================
-- PERSONAL-SOLL — Default-Werte vorbelegen
-- ============================================================================
-- 
-- Setzt für jeden aktiven Verein einen sinnvollen Standard-Personalbedarf.
-- ÄNDERBAR: Vorstand/Admin können die Werte danach jederzeit im Dashboard
-- (Panel "📊 Personal-Übersicht") pro Verein anpassen.
--
-- WICHTIG — überschreibt nichts:
-- Das UPDATE greift NUR bei Vereinen die noch KEIN personal_soll haben
-- (NULL oder leeres {}). Vereine bei denen schon Werte gepflegt wurden
-- bleiben unangetastet.
--
-- Default-Bedarf pro Verein:
--   Vorstand            1
--   Stellv. Vorstand    1
--   Präventionsbeauftr. 1
--   Ausgabe             2
--   Grower              5
--   Springer            2
--   Sicherheit          0  (nicht gespeichert — Panel zeigt automatisch 0)
--   Reinigung           0  (nicht gespeichert — Panel zeigt automatisch 0)
--   Head Grower         0  (nicht gespeichert — bei Bedarf manuell setzen)
--
-- 0-Werte werden bewusst NICHT gespeichert — das Panel zeigt fehlende Rollen
-- ohnehin als "kein Bedarf / Soll 0" an. Das hält das JSONB schlank.
-- ============================================================================

UPDATE csc_vereine
SET personal_soll = jsonb_build_object(
  'vorstand',        1,
  'stellv_vorstand', 1,
  'praevention',     1,
  'ausgabe',         2,
  'grower',          5,
  'springer',        2
)
WHERE aktiv = true
  AND (personal_soll IS NULL OR personal_soll = '{}'::jsonb);


-- ── Migration loggen ───────────────────────────────────────────────────────
INSERT INTO csc_migration_log (migration_id, beschreibung, autor, notizen)
VALUES (
  '2026-05-16_personal_soll_defaults',
  'Personal-Soll mit Standard-Werten vorbelegt für alle aktiven Vereine ohne eigene Werte: Vorstand 1, Stellv. Vorstand 1, Prävention 1, Ausgabe 2, Grower 5, Springer 2. Sicherheit/Reinigung/Head Grower bleiben 0 (nicht gespeichert). Pro Verein im Dashboard änderbar.',
  'andre.reiche@mariana-cannabis.de',
  'Betroffen: csc_vereine.personal_soll — nur Vereine mit leerem/NULL personal_soll'
)
ON CONFLICT (migration_id) DO NOTHING;


-- ── Verifikation ──────────────────────────────────────────────────────────
-- Zeigt wie viele Vereine jetzt welches Soll haben
SELECT 
  personal_soll,
  count(*) AS anzahl_vereine
FROM csc_vereine
WHERE aktiv = true
GROUP BY personal_soll
ORDER BY anzahl_vereine DESC;

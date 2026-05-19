-- ============================================================================
-- Feature: KFZ-Nutzung für den Verein (Kilometerpauschale)
-- ----------------------------------------------------------------------------
-- Neue Spalte für den Bewerbungsbogen. Der Bewerber gibt an, ob er sein
-- eigenes Fahrzeug bei Bedarf gegen Kilometerpauschale für den Verein
-- einsetzen könnte (z. B. für Transporte).
--
-- WICHTIG: Dieses SQL im Supabase-SQL-Editor ausführen, BEVOR die neue
-- bewerbung.html online geht. Sonst schlägt das Absenden des Bogens fehl,
-- weil die Spalte beim Insert noch nicht existiert.
--
-- Projekt: gvzayggvtlychyjbnsgv
-- ============================================================================

ALTER TABLE public.csc_bewerbungen
  ADD COLUMN IF NOT EXISTS kfz_fuer_verein text;

COMMENT ON COLUMN public.csc_bewerbungen.kfz_fuer_verein IS
  'Kann der Bewerber sein eigenes Fahrzeug gegen Kilometerpauschale für den Verein einsetzen? Werte: ja | nein | nach_absprache | NULL (keine Angabe / kein eigenes Fahrzeug)';

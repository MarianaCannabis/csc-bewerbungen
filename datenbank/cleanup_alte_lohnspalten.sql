-- ============================================================================
--  Aufraeum-Schritt: alte Lohn-/Vertragsspalten aus csc_bewerbungen entfernen
--  csc-bewerbungen · Supabase gvzayggvtlychyjbnsgv
--
--  Diese vier Spalten wurden frueher im Bewerbungsbogen erhoben. Seit dem
--  Umbau werden Vertragsdaten getrennt in csc_vertragsdaten gespeichert;
--  Bewerbungsbogen und Dashboard greifen NICHT mehr auf diese Spalten zu.
--
--  Dieser Schritt entfernt die alten Spalten endgueltig - inklusive der dort
--  noch gespeicherten Alt-Daten frueherer Bewerbungen (Datenminimierung,
--  Art. 5 Abs. 1 lit. c DSGVO).
--
--  ACHTUNG: unwiderruflich. Vorher sicherstellen, dass die aktuelle
--  Status-Seite und das aktuelle Dashboard live sind (sind sie bereits).
--
--  Ausfuehren: Supabase SQL Editor -> einfuegen -> Run
--  Idempotent: dank IF EXISTS gefahrlos auch erneut ausfuehrbar.
-- ============================================================================

ALTER TABLE csc_bewerbungen
  DROP COLUMN IF EXISTS steuer_id,
  DROP COLUMN IF EXISTS sv_nummer,
  DROP COLUMN IF EXISTS iban,
  DROP COLUMN IF EXISTS krankenkasse;

-- Schema-Cache der API neu laden, damit die entfernten Spalten sofort
-- aus der API-Sicht verschwinden.
NOTIFY pgrst, 'reload schema';

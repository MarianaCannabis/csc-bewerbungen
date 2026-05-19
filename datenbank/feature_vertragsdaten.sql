-- ============================================================================
--  Migration: Vertragsdaten (umfangreich)  ·  csc-bewerbungen
--  Supabase gvzayggvtlychyjbnsgv
--
--  Sensible Personaldaten fuer Arbeitsvertrag + Lohnabrechnung. Werden NICHT
--  im Bewerbungsbogen erhoben, sondern erst nach Annahme ueber die Status-Seite.
--  Eigene Tabelle, nur fuer Admins lesbar - Vorstaende nicht.
--
--  Diese Datei ist idempotent und kann gefahrlos erneut ausgefuehrt werden
--  (auch wenn die erste, kleinere Version bereits lief).
--  Ausfuehren: Supabase SQL Editor -> einfuegen -> Run
-- ============================================================================

-- 1) Tabelle ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS csc_vertragsdaten (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bewerbung_id    uuid NOT NULL UNIQUE REFERENCES csc_bewerbungen(id) ON DELETE CASCADE,
  eingereicht_am  timestamptz NOT NULL DEFAULT now(),
  aktualisiert_am timestamptz NOT NULL DEFAULT now()
);

-- Datenspalten - ADD COLUMN IF NOT EXISTS ergaenzt auch eine bereits
-- bestehende Tabelle aus der ersten Migrations-Version.
ALTER TABLE csc_vertragsdaten
  ADD COLUMN IF NOT EXISTS steuer_id                      text,
  ADD COLUMN IF NOT EXISTS sv_nummer                      text,
  ADD COLUMN IF NOT EXISTS iban                           text,
  ADD COLUMN IF NOT EXISTS kk_name                        text,
  ADD COLUMN IF NOT EXISTS kk_mitgl                       text,
  ADD COLUMN IF NOT EXISTS geburtsname                    text,
  ADD COLUMN IF NOT EXISTS familienstand                  text,
  ADD COLUMN IF NOT EXISTS kinder_anzahl                  integer,
  ADD COLUMN IF NOT EXISTS steuerklasse                   text,
  ADD COLUMN IF NOT EXISTS konfession                     text,
  ADD COLUMN IF NOT EXISTS kv_art                         text,
  ADD COLUMN IF NOT EXISTS rv_befreiung                   text,
  ADD COLUMN IF NOT EXISTS kontoinhaber                   text,
  ADD COLUMN IF NOT EXISTS schulabschluss                 text,
  ADD COLUMN IF NOT EXISTS berufsausbildung               text,
  ADD COLUMN IF NOT EXISTS weitere_beschaeftigung         text,
  ADD COLUMN IF NOT EXISTS weitere_beschaeftigung_details text,
  ADD COLUMN IF NOT EXISTS notfall_name                   text,
  ADD COLUMN IF NOT EXISTS notfall_telefon                text;

COMMENT ON TABLE csc_vertragsdaten IS
  'Vertrags- und Lohndaten fuer angenommene Bewerber. Getrennt von csc_bewerbungen, '
  'nur fuer Hauptverein-Admins lesbar. Loescht mit der Bewerbung mit (CASCADE).';

-- 2) Row Level Security -----------------------------------------------------
ALTER TABLE csc_vertragsdaten ENABLE ROW LEVEL SECURITY;

-- SELECT nur fuer Admins (Vorstaende sehen die Daten NICHT).
-- csc_is_hauptverein_admin() ist die im Projekt etablierte Admin-Pruefung.
DROP POLICY IF EXISTS vertragsdaten_admin_select ON csc_vertragsdaten;
CREATE POLICY vertragsdaten_admin_select ON csc_vertragsdaten
  FOR SELECT TO authenticated
  USING (csc_is_hauptverein_admin());

-- DELETE nur fuer Admins (eigene Loeschfrist: nach Vertragsabschluss loeschbar).
DROP POLICY IF EXISTS vertragsdaten_admin_delete ON csc_vertragsdaten;
CREATE POLICY vertragsdaten_admin_delete ON csc_vertragsdaten
  FOR DELETE TO authenticated
  USING (csc_is_hauptverein_admin());

-- Kein INSERT/UPDATE per Policy: Schreiben nur ueber save_vertragsdaten().

-- 3) Speichern (Status-Seite) -----------------------------------------------
--    jsonb-Parameter: neue Felder lassen sich kuenftig ohne Signaturwechsel
--    ergaenzen. Token-geprueft, nur bei Status 'angenommen'.
DROP FUNCTION IF EXISTS save_vertragsdaten(text,text,text,text,text,text);
DROP FUNCTION IF EXISTS save_vertragsdaten(text,jsonb);

CREATE OR REPLACE FUNCTION save_vertragsdaten(p_token text, p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_id     uuid;
  v_status text;
BEGIN
  SELECT id, status INTO v_id, v_status
  FROM csc_bewerbungen WHERE bewerber_token = p_token;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF v_status IS DISTINCT FROM 'angenommen' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_angenommen');
  END IF;

  INSERT INTO csc_vertragsdaten (
    bewerbung_id, steuer_id, sv_nummer, iban, kk_name, kk_mitgl,
    geburtsname, familienstand, kinder_anzahl, steuerklasse, konfession,
    kv_art, rv_befreiung, kontoinhaber, schulabschluss, berufsausbildung,
    weitere_beschaeftigung, weitere_beschaeftigung_details,
    notfall_name, notfall_telefon
  ) VALUES (
    v_id,
    nullif(btrim(coalesce(p_data->>'steuer_id','')),''),
    nullif(btrim(coalesce(p_data->>'sv_nummer','')),''),
    nullif(btrim(coalesce(p_data->>'iban','')),''),
    nullif(btrim(coalesce(p_data->>'kk_name','')),''),
    nullif(btrim(coalesce(p_data->>'kk_mitgl','')),''),
    nullif(btrim(coalesce(p_data->>'geburtsname','')),''),
    nullif(btrim(coalesce(p_data->>'familienstand','')),''),
    nullif(btrim(coalesce(p_data->>'kinder_anzahl','')),'')::int,
    nullif(btrim(coalesce(p_data->>'steuerklasse','')),''),
    nullif(btrim(coalesce(p_data->>'konfession','')),''),
    nullif(btrim(coalesce(p_data->>'kv_art','')),''),
    nullif(btrim(coalesce(p_data->>'rv_befreiung','')),''),
    nullif(btrim(coalesce(p_data->>'kontoinhaber','')),''),
    nullif(btrim(coalesce(p_data->>'schulabschluss','')),''),
    nullif(btrim(coalesce(p_data->>'berufsausbildung','')),''),
    nullif(btrim(coalesce(p_data->>'weitere_beschaeftigung','')),''),
    nullif(btrim(coalesce(p_data->>'weitere_beschaeftigung_details','')),''),
    nullif(btrim(coalesce(p_data->>'notfall_name','')),''),
    nullif(btrim(coalesce(p_data->>'notfall_telefon','')),'')
  )
  ON CONFLICT (bewerbung_id) DO UPDATE SET
    steuer_id                      = EXCLUDED.steuer_id,
    sv_nummer                      = EXCLUDED.sv_nummer,
    iban                           = EXCLUDED.iban,
    kk_name                        = EXCLUDED.kk_name,
    kk_mitgl                       = EXCLUDED.kk_mitgl,
    geburtsname                    = EXCLUDED.geburtsname,
    familienstand                  = EXCLUDED.familienstand,
    kinder_anzahl                  = EXCLUDED.kinder_anzahl,
    steuerklasse                   = EXCLUDED.steuerklasse,
    konfession                     = EXCLUDED.konfession,
    kv_art                         = EXCLUDED.kv_art,
    rv_befreiung                   = EXCLUDED.rv_befreiung,
    kontoinhaber                   = EXCLUDED.kontoinhaber,
    schulabschluss                 = EXCLUDED.schulabschluss,
    berufsausbildung               = EXCLUDED.berufsausbildung,
    weitere_beschaeftigung         = EXCLUDED.weitere_beschaeftigung,
    weitere_beschaeftigung_details = EXCLUDED.weitere_beschaeftigung_details,
    notfall_name                   = EXCLUDED.notfall_name,
    notfall_telefon                = EXCLUDED.notfall_telefon,
    aktualisiert_am                = now();

  RETURN jsonb_build_object('ok', true);
END;
$fn$;

GRANT EXECUTE ON FUNCTION save_vertragsdaten(text, jsonb) TO anon, authenticated;

-- 4) Vorbelegung der Status-Seite -------------------------------------------
--    Liefert dem Bewerber NUR seine eigenen Vertragsdaten (Token-geprueft).
CREATE OR REPLACE FUNCTION get_vertragsdaten_status(p_token text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_id uuid;
  v_vd csc_vertragsdaten%ROWTYPE;
BEGIN
  SELECT id INTO v_id FROM csc_bewerbungen WHERE bewerber_token = p_token;
  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false);
  END IF;

  SELECT * INTO v_vd FROM csc_vertragsdaten WHERE bewerbung_id = v_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'erfasst', false);
  END IF;

  RETURN jsonb_build_object('ok', true, 'erfasst', true) || to_jsonb(v_vd);
END;
$fn$;

GRANT EXECUTE ON FUNCTION get_vertragsdaten_status(text) TO anon, authenticated;

-- ============================================================================
--  OPTIONAL - erst ausfuehren, wenn die neue Status-Seite live ist:
--  alte Spalten aus csc_bewerbungen entfernen (loescht dortige Alt-Daten).
-- ----------------------------------------------------------------------------
-- ALTER TABLE csc_bewerbungen
--   DROP COLUMN IF EXISTS steuer_id,
--   DROP COLUMN IF EXISTS sv_nummer,
--   DROP COLUMN IF EXISTS iban,
--   DROP COLUMN IF EXISTS krankenkasse;
-- ============================================================================

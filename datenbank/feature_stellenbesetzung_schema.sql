-- ============================================================================
-- FEATURE: Stellenbesetzung — Einstellungs-Details + Personal-Soll
-- ============================================================================
--
-- Was dieses Script anlegt:
--
--   1. csc_bewerbungen.eingestellt_details (JSONB)
--      Welche Rolle(n) + welcher Vertrag der Bewerber bekommen soll.
--      Format: [{"rolle":"ausgabe","vertrag":"minijob"},
--               {"rolle":"grower","vertrag":"ehrenamt"}]
--      Editierbar ab Status "in_pruefung", Pflicht ab "warteliste".
--
--   2. csc_vereine.personal_soll (JSONB)
--      Wie viele Mitarbeiter pro Rolle der Verein sucht.
--      Format: {"grower":5,"ausgabe":3,"praevention":1,"springer":2,"vorstand":1}
--
--   3. csc_set_personal_soll(verein_id, soll) — SECURITY DEFINER Setter
--      Da Zweigverein-Vorstände KEIN generelles UPDATE-Recht auf csc_vereine
--      haben (und auch nicht bekommen sollen — sonst könnten sie aktiv/name/
--      bewerbungen_offen ändern), läuft das Setzen von personal_soll über
--      diese Function mit eingebautem Permission-Check.
--
--   Vertragstypen: 'minijob', 'teilzeit', 'vollzeit', 'ehrenamt'
--   KCanG §17: Grower-Rolle nur 'minijob' oder 'ehrenamt' — wird im
--   Frontend erzwungen (Dashboard + Bewerbungsbogen).
-- ============================================================================


-- ── 1) Spalte für Einstellungs-Details ─────────────────────────────────────
ALTER TABLE csc_bewerbungen
  ADD COLUMN IF NOT EXISTS eingestellt_details JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN csc_bewerbungen.eingestellt_details IS
  'Array von {rolle, vertrag}-Objekten — für welche Position(en) + Vertrag der Bewerber eingestellt wird. Editierbar ab Status in_pruefung.';


-- ── 2) Spalte für Personal-Soll pro Verein ─────────────────────────────────
ALTER TABLE csc_vereine
  ADD COLUMN IF NOT EXISTS personal_soll JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN csc_vereine.personal_soll IS
  'Objekt {rolle: anzahl} — wie viele Mitarbeiter der Verein pro Rolle sucht.';


-- ── 3) Setter-Function für personal_soll (mit Permission-Check) ────────────
CREATE OR REPLACE FUNCTION csc_set_personal_soll(p_verein_id UUID, p_soll JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ctx          RECORD;
  v_key          TEXT;
  v_val          JSONB;
BEGIN
  -- User-Kontext holen (rolle, verein_id, ist_admin)
  SELECT * INTO v_ctx FROM csc_current_user_context() LIMIT 1;

  IF v_ctx IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Kein User-Kontext.');
  END IF;

  -- Permission: Hauptverein-Admin darf jeden Verein, Zweigverein-Vorstand
  -- nur den EIGENEN Verein. zweigverein_lesen darf NICHT.
  IF NOT (
    v_ctx.ist_admin = true
    OR (v_ctx.rolle = 'zweigverein_vorstand' AND v_ctx.verein_id = p_verein_id)
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Keine Berechtigung — nur Admin oder Vorstand des eigenen Vereins.'
    );
  END IF;

  -- Validierung: p_soll muss ein Objekt sein, Werte müssen nicht-negative Zahlen
  IF jsonb_typeof(p_soll) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'personal_soll muss ein JSON-Objekt sein.');
  END IF;

  FOR v_key, v_val IN SELECT * FROM jsonb_each(p_soll) LOOP
    IF jsonb_typeof(v_val) <> 'number' THEN
      RETURN jsonb_build_object('ok', false, 'error',
        format('Wert für "%s" ist keine Zahl.', v_key));
    END IF;
    IF (v_val)::numeric < 0 THEN
      RETURN jsonb_build_object('ok', false, 'error',
        format('Wert für "%s" darf nicht negativ sein.', v_key));
    END IF;
  END LOOP;

  -- Update durchführen
  UPDATE csc_vereine SET personal_soll = p_soll WHERE id = p_verein_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Verein nicht gefunden.');
  END IF;

  RETURN jsonb_build_object('ok', true, 'personal_soll', p_soll);
END;
$$;

-- Nur authenticated darf die Function callen (anon nicht)
REVOKE ALL ON FUNCTION csc_set_personal_soll(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION csc_set_personal_soll(UUID, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION csc_set_personal_soll(UUID, JSONB) TO authenticated;


-- ── 4) Migration loggen ────────────────────────────────────────────────────
INSERT INTO csc_migration_log (migration_id, beschreibung, autor, notizen)
VALUES (
  '2026-05-16_stellenbesetzung_schema',
  'Feature Stellenbesetzung: Spalte eingestellt_details (JSONB) auf csc_bewerbungen — welche Rolle(n) + Vertrag der Bewerber bekommt. Spalte personal_soll (JSONB) auf csc_vereine — Personalbedarf pro Rolle. Setter-Function csc_set_personal_soll mit Permission-Check (Vorstand nur eigener Verein).',
  'andre.reiche@mariana-cannabis.de',
  'Betroffen: csc_bewerbungen, csc_vereine, neue Function csc_set_personal_soll'
)
ON CONFLICT (migration_id) DO NOTHING;


-- ── Verifikation ──────────────────────────────────────────────────────────
SELECT 
  table_name, 
  column_name, 
  data_type, 
  column_default
FROM information_schema.columns
WHERE (table_name = 'csc_bewerbungen' AND column_name = 'eingestellt_details')
   OR (table_name = 'csc_vereine'     AND column_name = 'personal_soll')
ORDER BY table_name;

SELECT proname, prosecdef AS is_security_definer
FROM pg_proc WHERE proname = 'csc_set_personal_soll';

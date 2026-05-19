-- ============================================================================
-- FEATURE: Vereins-Stammdaten + Onboarding (Etappe 5a)
-- ============================================================================
--
-- Was dieses Script anlegt:
--
--   1. csc_vereine.stammdaten (JSONB)
--      Betriebsdaten des Vereins für die Personalbedarfs-Berechnung.
--      Format: {
--        "mitglieder":        500,   -- Mitgliederzahl
--        "oeffnungstage":     4,     -- Ausgabe-Tage pro Woche
--        "oeffnungsstunden":  5,     -- Öffnungsstunden pro Ausgabe-Tag
--        "vorbereitung":      1,     -- Vor-/Nachbereitung in Stunden pro Tag
--        "ausgabe_punkte":    1      -- parallele Ausgabe-Theken (1 oder 2)
--      }
--
--   2. csc_vereine.onboarding_erledigt (BOOLEAN)
--      Flag — true sobald der Vorstand die Stammdaten-Abfrage durchlaufen hat.
--      Steuert ob beim Login das Onboarding-Modal erscheint.
--
--   3. csc_set_vereins_stammdaten(verein_id, stammdaten) — SECURITY DEFINER
--      Analog zu csc_set_personal_soll: Zweigverein-Vorstände haben kein
--      generelles UPDATE-Recht auf csc_vereine, deshalb läuft das Setzen
--      über diese Function mit Permission-Check. Setzt zugleich
--      onboarding_erledigt = true.
-- ============================================================================


-- ── 1) Spalte für Stammdaten ───────────────────────────────────────────────
ALTER TABLE csc_vereine
  ADD COLUMN IF NOT EXISTS stammdaten JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN csc_vereine.stammdaten IS
  'Betriebsdaten für Personalbedarfs-Berechnung: mitglieder, oeffnungstage, oeffnungsstunden, vorbereitung, ausgabe_punkte.';


-- ── 2) Spalte für Onboarding-Flag ──────────────────────────────────────────
ALTER TABLE csc_vereine
  ADD COLUMN IF NOT EXISTS onboarding_erledigt BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN csc_vereine.onboarding_erledigt IS
  'true sobald der Vorstand die einmalige Stammdaten-Abfrage durchlaufen hat.';


-- ── 3) Setter-Function für stammdaten (mit Permission-Check) ───────────────
CREATE OR REPLACE FUNCTION csc_set_vereins_stammdaten(p_verein_id UUID, p_stammdaten JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ctx  RECORD;
  v_key  TEXT;
  v_val  JSONB;
BEGIN
  -- User-Kontext holen (rolle, verein_id, ist_admin)
  SELECT * INTO v_ctx FROM csc_current_user_context() LIMIT 1;

  IF v_ctx IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Kein User-Kontext.');
  END IF;

  -- Permission: Hauptverein-Admin darf jeden Verein, Zweigverein-Vorstand
  -- nur den EIGENEN. zweigverein_lesen darf NICHT.
  IF NOT (
    v_ctx.ist_admin = true
    OR (v_ctx.rolle = 'zweigverein_vorstand' AND v_ctx.verein_id = p_verein_id)
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Keine Berechtigung — nur Admin oder Vorstand des eigenen Vereins.'
    );
  END IF;

  -- Validierung: muss ein Objekt sein, alle Werte nicht-negative Zahlen
  IF jsonb_typeof(p_stammdaten) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'stammdaten muss ein JSON-Objekt sein.');
  END IF;

  FOR v_key, v_val IN SELECT * FROM jsonb_each(p_stammdaten) LOOP
    IF jsonb_typeof(v_val) <> 'number' THEN
      RETURN jsonb_build_object('ok', false, 'error',
        format('Wert für "%s" ist keine Zahl.', v_key));
    END IF;
    IF (v_val)::numeric < 0 THEN
      RETURN jsonb_build_object('ok', false, 'error',
        format('Wert für "%s" darf nicht negativ sein.', v_key));
    END IF;
  END LOOP;

  -- Update: Stammdaten setzen UND Onboarding als erledigt markieren
  UPDATE csc_vereine
  SET stammdaten = p_stammdaten,
      onboarding_erledigt = true
  WHERE id = p_verein_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Verein nicht gefunden.');
  END IF;

  RETURN jsonb_build_object('ok', true, 'stammdaten', p_stammdaten);
END;
$$;

-- Nur authenticated darf die Function callen (anon nicht)
REVOKE ALL ON FUNCTION csc_set_vereins_stammdaten(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION csc_set_vereins_stammdaten(UUID, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION csc_set_vereins_stammdaten(UUID, JSONB) TO authenticated;


-- ── 4) Migration loggen ────────────────────────────────────────────────────
INSERT INTO csc_migration_log (migration_id, beschreibung, autor, notizen)
VALUES (
  '2026-05-16_vereins_stammdaten',
  'Feature Onboarding (Etappe 5a): Spalte stammdaten (JSONB) auf csc_vereine — Betriebsdaten für Personalbedarfs-Berechnung. Spalte onboarding_erledigt (BOOLEAN). Setter-Function csc_set_vereins_stammdaten mit Permission-Check, setzt zugleich onboarding_erledigt=true.',
  'andre.reiche@mariana-cannabis.de',
  'Betroffen: csc_vereine (2 neue Spalten), neue Function csc_set_vereins_stammdaten'
)
ON CONFLICT (migration_id) DO NOTHING;


-- ── Verifikation ──────────────────────────────────────────────────────────
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'csc_vereine'
  AND column_name IN ('stammdaten', 'onboarding_erledigt')
ORDER BY column_name;

SELECT proname, prosecdef AS is_security_definer
FROM pg_proc WHERE proname = 'csc_set_vereins_stammdaten';

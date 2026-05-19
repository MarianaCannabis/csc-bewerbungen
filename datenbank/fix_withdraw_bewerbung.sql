-- ============================================================================
-- FIX Bug 1: DSGVO-Selbstlöschung — Storage-API statt direkten storage.objects-DELETE
-- ============================================================================
-- 
-- Hintergrund:
-- Supabase blockt seit einer Plattform-Änderung "DELETE FROM storage.objects"
-- auch in SECURITY DEFINER PL/pgSQL-Funktionen mit dem Fehler:
--   "Direct deletion from storage tables is not allowed. Use the Storage API instead."
-- 
-- Lösung:
-- 1. Alte csc_withdraw_bewerbung() wird DROPPED. Wer den alten RPC-Call noch
--    macht, läuft sonst weiter ins Storage-Limit.
-- 2. NEUE Function csc_withdraw_bewerbung_db_only(p_bewerbung_id UUID) — 
--    löscht NUR DB-Records. Wird ausschließlich von der Edge Function 
--    "withdraw-bewerbung" aufgerufen, die vorher Storage via API geleert hat.
-- 3. csc_withdraw_bewerbung(token) bleibt als DEPRECATED-Stub, der einen
--    klaren Fehler zurückgibt — falls noch irgendwo der alte RPC-Call lebt.
-- ============================================================================

-- ── ALTE Funktion entfernen ────────────────────────────────────────────────
DROP FUNCTION IF EXISTS csc_withdraw_bewerbung(TEXT);


-- ── NEUE Funktion: DB-only Cleanup, wird von Edge Function gerufen ─────────
CREATE OR REPLACE FUNCTION csc_withdraw_bewerbung_db_only(p_bewerbung_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email           TEXT;
  v_vorname         TEXT;
  v_anhaenge_count  INTEGER := 0;
  v_notizen_count   INTEGER := 0;
  v_changes_count   INTEGER := 0;
BEGIN
  -- Existenz-Check
  SELECT email, vorname 
    INTO v_email, v_vorname
  FROM csc_bewerbungen
  WHERE id = p_bewerbung_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false, 
      'error', 'Bewerbung nicht gefunden.'
    );
  END IF;

  -- Anhang-Records löschen (Storage-Files hat die Edge Function bereits 
  -- via Storage-API gelöscht — wir entfernen hier nur die Metadaten)
  WITH del AS (
    DELETE FROM csc_bewerbung_anhaenge 
    WHERE bewerbung_id = p_bewerbung_id
    RETURNING 1
  )
  SELECT count(*) INTO v_anhaenge_count FROM del;

  -- Notizen löschen
  WITH del AS (
    DELETE FROM csc_bewerbung_notizen 
    WHERE bewerbung_id = p_bewerbung_id
    RETURNING 1
  )
  SELECT count(*) INTO v_notizen_count FROM del;

  -- Audit/Changes-Log löschen (DSGVO-konform mitlöschen, da User Recht auf
  -- vollständige Löschung hat — der einzige Audit-Trail der bleibt ist im 
  -- Edge-Function-Log mit der ID, ohne PII)
  WITH del AS (
    DELETE FROM csc_bewerbung_changes 
    WHERE bewerbung_id = p_bewerbung_id
    RETURNING 1
  )
  SELECT count(*) INTO v_changes_count FROM del;

  -- Bewerbung selbst löschen
  DELETE FROM csc_bewerbungen WHERE id = p_bewerbung_id;

  RETURN jsonb_build_object(
    'ok', true,
    'message', 'Bewerbung vollständig aus der Datenbank gelöscht.',
    'vorname', v_vorname,
    'deleted', jsonb_build_object(
      'anhaenge', v_anhaenge_count,
      'notizen',  v_notizen_count,
      'changes',  v_changes_count
    )
  );
END;
$$;

-- Service-Role hat sowieso BYPASS-Rechte; explizit den authenticated-Grant 
-- NICHT geben, damit nur die Edge Function (mit Service-Role) das callen kann
REVOKE ALL ON FUNCTION csc_withdraw_bewerbung_db_only(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION csc_withdraw_bewerbung_db_only(UUID) FROM authenticated;
REVOKE ALL ON FUNCTION csc_withdraw_bewerbung_db_only(UUID) FROM anon;
-- service_role hat per default Zugriff


-- ── Deprecated-Stub: alter Aufruf zeigt klaren Fehler ──────────────────────
CREATE OR REPLACE FUNCTION csc_withdraw_bewerbung(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object(
    'ok', false,
    'error', 'Diese Funktion ist veraltet. Bitte Edge Function "withdraw-bewerbung" verwenden.',
    'deprecated', true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION csc_withdraw_bewerbung(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION csc_withdraw_bewerbung(TEXT) TO authenticated;


-- ── Verify ─────────────────────────────────────────────────────────────────
SELECT 
  proname,
  prosecdef AS is_security_definer,
  pg_get_function_arguments(oid) AS args
FROM pg_proc
WHERE proname IN ('csc_withdraw_bewerbung', 'csc_withdraw_bewerbung_db_only')
ORDER BY proname;

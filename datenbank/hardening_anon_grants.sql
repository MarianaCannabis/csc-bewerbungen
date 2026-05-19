-- ============================================================================
-- SEKUNDÄRE HARDENINGS — Defense in Depth
-- ============================================================================
--
-- Stand: nach Drop von csc_bewerbungen_select_self_token. 
-- Diese Migration adressiert die zwei verbliebenen Schwächen aus dem letzten 
-- Audit:
--
--   A) csc_anhaenge_insert_public hat with_check = null → anon kann Anhang-
--      Records für BELIEBIGE bewerbung_id einfügen, auch zu fremden 
--      Bewerbungen (sofern man die ID erraten könnte — UUID, praktisch 
--      unmöglich, aber konzeptuell offen).
--      Fix: with_check zwingt die referenzierte Bewerbung muss existieren.
--
--   B) anon hat Tabellen-GRANTs für DELETE, UPDATE, TRUNCATE auf allen 
--      csc_-Tabellen. RLS blockt das alles, aber sauberer ist es, anon nur 
--      genau die Privilegien zu geben die wirklich gebraucht werden 
--      (Belt-and-Suspenders gegen RLS-Bugs in der Zukunft).
--
-- Was anon WIRKLICH können soll (Bewerbungs-Bogen-Flow):
--   - csc_bewerbungen:        INSERT
--   - csc_bewerbung_anhaenge: INSERT (mit with_check)
--   - csc_vereine:            SELECT  (für die Vereins-Auswahl im Bogen, 
--                                       gefiltert durch RLS auf aktiv=true 
--                                       AND bewerbungen_offen=true)
--
-- ALLES andere für anon: REVOKE.
-- ============================================================================


-- ── A) ANHANG-INSERT-POLICY VERSCHÄRFEN ─────────────────────────────────────

-- Helper: prüft Existenz einer Bewerbung (SECURITY DEFINER, weil anon 
-- selbst kein SELECT auf csc_bewerbungen hat).
-- Bewerbungs-IDs sind UUIDs (random 128-bit) → keine Brute-Force-Gefahr.
CREATE OR REPLACE FUNCTION csc_bewerbung_exists(p_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM csc_bewerbungen WHERE id = p_id)
$$;

GRANT EXECUTE ON FUNCTION csc_bewerbung_exists(UUID) TO anon, authenticated;
REVOKE EXECUTE ON FUNCTION csc_bewerbung_exists(UUID) FROM public;

-- Anhang-Insert nur noch wenn referenzierte Bewerbung existiert
DROP POLICY IF EXISTS csc_anhaenge_insert_public ON csc_bewerbung_anhaenge;
CREATE POLICY csc_anhaenge_insert_public
  ON csc_bewerbung_anhaenge
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (csc_bewerbung_exists(bewerbung_id));


-- ── B) ANON-TABELLEN-GRANTS ABHÄRTEN ───────────────────────────────────────

-- csc_bewerbungen: nur INSERT
REVOKE ALL ON TABLE csc_bewerbungen FROM anon;
GRANT  INSERT ON TABLE csc_bewerbungen TO anon;

-- csc_bewerbung_anhaenge: nur INSERT
REVOKE ALL ON TABLE csc_bewerbung_anhaenge FROM anon;
GRANT  INSERT ON TABLE csc_bewerbung_anhaenge TO anon;

-- csc_vereine: nur SELECT (für Vereins-Auswahl, RLS filtert auf aktive)
REVOKE ALL ON TABLE csc_vereine FROM anon;
GRANT  SELECT ON TABLE csc_vereine TO anon;

-- csc_bewerbung_notizen, csc_bewerbung_changes: anon braucht gar nichts
REVOKE ALL ON TABLE csc_bewerbung_notizen FROM anon;
REVOKE ALL ON TABLE csc_bewerbung_changes FROM anon;

-- csc_user_profiles, csc_dashboard_user: anon braucht gar nichts
REVOKE ALL ON TABLE csc_user_profiles FROM anon;
REVOKE ALL ON TABLE csc_dashboard_user FROM anon;


-- ============================================================================
-- VERIFIKATION
-- ============================================================================

-- 1) Anhang-Policy hat jetzt with_check
SELECT 
  policyname, 
  roles, 
  cmd, 
  qual AS using_expression,
  with_check AS with_check_expression
FROM pg_policies 
WHERE tablename = 'csc_bewerbung_anhaenge'
  AND policyname = 'csc_anhaenge_insert_public';

-- 2) anon-GRANTs auf den csc_-Tabellen — erwartet:
--    csc_bewerbungen          → INSERT
--    csc_bewerbung_anhaenge   → INSERT
--    csc_vereine              → SELECT
--    csc_bewerbung_notizen    → (nichts)
--    csc_bewerbung_changes    → (nichts)
--    csc_user_profiles        → (nichts)
--    csc_dashboard_user       → (nichts)
SELECT 
  table_name, 
  privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'anon'
  AND table_name LIKE 'csc_%'
ORDER BY table_name, privilege_type;

-- 3) Helper-Function ist da
SELECT proname, prosecdef AS is_security_definer
FROM pg_proc
WHERE proname = 'csc_bewerbung_exists';

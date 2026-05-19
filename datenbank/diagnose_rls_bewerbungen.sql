-- ============================================================================
-- DIAGNOSE: RLS-Status auf csc_bewerbungen (für 30-Sek-Leak-Bug)
-- ============================================================================
-- Erwartung: EINE oder MEHRERE SELECT-Policies, die nach Verein filtern.
-- Wenn keine SELECT-Policy da ist → RLS aktiv aber ohne Policy = alle Reihen
--                                    sichtbar für jeden authenticated user.
-- Wenn eine Policy mit "true" oder ohne Verein-Filter da ist → genau das Leck.
-- ============================================================================

-- 1) Ist RLS überhaupt aktiv?
SELECT 
  c.relname           AS tabelle,
  c.relrowsecurity    AS rls_aktiv,
  c.relforcerowsecurity AS rls_force_aktiv
FROM pg_class c
WHERE c.relname IN (
  'csc_bewerbungen', 
  'csc_bewerbung_anhaenge', 
  'csc_bewerbung_notizen',
  'csc_bewerbung_changes',
  'csc_vereine',
  'csc_user_profiles',
  'csc_dashboard_user'
)
ORDER BY c.relname;


-- 2) Alle Policies auf csc_bewerbungen — DIESE sind der Schlüssel
SELECT 
  policyname,
  roles,
  cmd                 AS operation,
  qual                AS using_expression,
  with_check          AS with_check_expression,
  permissive
FROM pg_policies
WHERE tablename = 'csc_bewerbungen'
ORDER BY cmd, policyname;


-- 3) Alle Policies auf den anderen kritischen Tabellen
SELECT 
  tablename, 
  policyname, 
  cmd, 
  qual AS using_expression
FROM pg_policies
WHERE tablename IN (
  'csc_bewerbung_anhaenge', 
  'csc_bewerbung_notizen',
  'csc_bewerbung_changes',
  'csc_vereine',
  'csc_user_profiles'
)
ORDER BY tablename, cmd, policyname;


-- 4) Welche Rollen haben direkten GRANT auf csc_bewerbungen?
SELECT 
  grantee, 
  privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'csc_bewerbungen'
ORDER BY grantee, privilege_type;


-- 5) Sanity-Check: Wie löst die SECURITY-DEFINER-Function csc_current_user_context
--    "Admin" vs "Verein-Vorstand" auf? (Sehe ich brauchen wir die Funktion-Logik.)
SELECT 
  proname, 
  prosecdef AS is_security_definer,
  pg_get_function_arguments(oid) AS args,
  pg_get_function_result(oid) AS returns
FROM pg_proc
WHERE proname IN ('csc_current_user_context', 'csc_check_login_allowed')
ORDER BY proname;

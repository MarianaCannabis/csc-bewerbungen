-- ============================================================================
-- KRITISCHER FIX: RLS-Leck in csc_bewerbungen
-- ============================================================================
-- 
-- Was war kaputt:
-- ---------------
-- Es existierte eine Policy:
--   csc_bewerbungen_select_self_token  
--   ROLE: {anon, authenticated}  
--   CMD:  SELECT  
--   USING: (bewerber_token IS NOT NULL)
--
-- Da bewerber_token bei JEDER Bewerbung gesetzt ist (damit die Status-Seite
-- per Link funktioniert), bedeutete diese Policy faktisch:
--   "JEDER Browser mit anon-Key kann ALLE Bewerbungen sehen."
--
-- Das war ein massiver DSGVO-Verstoß. Der Client-Filter im Dashboard hat
-- das oberflächlich kaschiert, aber jeder mit DevTools / curl konnte
-- direkt über die Supabase REST-API alle 182 Vereine durchlesen.
--
-- Wieso die Policy ÜBERFLÜSSIG ist:
-- ---------------------------------
-- Die Bewerber-Status-Seite (status_index.html) wurde umgestellt auf die
-- Edge Function "get-bewerbung-status", die mit Service-Role server-seitig
-- nach Token filtert und NUR die unsensiblen Status-Felder zurückgibt.
-- Es gibt keinen anderen legitimen Anwendungsfall für die Policy.
--
-- VORAUSSETZUNG für dieses Script:
-- --------------------------------
-- - status_index.html Build 2026-05-15T2245 oder neuer muss live sein.
-- - Edge Function "get-bewerbung-status" muss deployed sein (war sie schon).
--
-- ============================================================================


-- ── 1) Die böse Policy ersatzlos droppen ────────────────────────────────────
DROP POLICY IF EXISTS csc_bewerbungen_select_self_token ON csc_bewerbungen;


-- ── 2) Update-Policies härten: {public} → {authenticated} ───────────────────
-- Hintergrund: Die Functions csc_is_hauptverein() / csc_current_user_rolle()
-- geben für anon zwar false zurück (kein auth.uid()), aber konzeptuell ist
-- es sauberer, Update-Policies erst gar nicht für anon zu prüfen. Das
-- spart auch CPU bei jeder anon-Anfrage.

DROP POLICY IF EXISTS csc_bewerbungen_update_hauptverein ON csc_bewerbungen;
CREATE POLICY csc_bewerbungen_update_hauptverein
  ON csc_bewerbungen
  FOR UPDATE
  TO authenticated
  USING (csc_is_hauptverein());

DROP POLICY IF EXISTS csc_bewerbungen_update_zweigverein_vorstand ON csc_bewerbungen;
CREATE POLICY csc_bewerbungen_update_zweigverein_vorstand
  ON csc_bewerbungen
  FOR UPDATE
  TO authenticated
  USING (
    csc_current_user_rolle() = 'zweigverein_vorstand'
    AND verein_id = csc_current_user_verein()
  );


-- ── 3) SELECT-Policy für hauptverein/zweigverein auch auf {authenticated} ──
-- Sind aktuell auf {public}, aber Functions verlangen ohnehin auth.uid().
-- Klarheit + Mini-Perf-Win.

DROP POLICY IF EXISTS csc_bewerbungen_select_hauptverein ON csc_bewerbungen;
CREATE POLICY csc_bewerbungen_select_hauptverein
  ON csc_bewerbungen
  FOR SELECT
  TO authenticated
  USING (csc_is_hauptverein());

DROP POLICY IF EXISTS csc_bewerbungen_select_zweigverein ON csc_bewerbungen;
CREATE POLICY csc_bewerbungen_select_zweigverein
  ON csc_bewerbungen
  FOR SELECT
  TO authenticated
  USING (
    csc_current_user_rolle() = ANY (ARRAY['zweigverein_vorstand'::text, 'zweigverein_lesen'::text])
    AND verein_id = csc_current_user_verein()
  );


-- ============================================================================
-- VERIFIKATION
-- ============================================================================

-- Nach dem Run sollte die SELECT-Liste der Policies für csc_bewerbungen so aussehen:
--   - csc_bewerbungen_select_hauptverein               | {authenticated} | SELECT
--   - csc_bewerbungen_select_vorstand_eigener_verein   | {authenticated} | SELECT
--   - csc_bewerbungen_select_zweigverein               | {authenticated} | SELECT
-- 
-- Die böse Policy csc_bewerbungen_select_self_token DARF NICHT MEHR auftauchen.

SELECT 
  policyname, 
  roles,
  cmd, 
  qual AS using_expression
FROM pg_policies 
WHERE tablename = 'csc_bewerbungen' 
ORDER BY cmd, policyname;


-- ============================================================================
-- ROLLBACK (für den Notfall — NUR wenn die Status-Seite zerschossen ist!)
-- ============================================================================
-- 
-- Falls die Bewerber-Status-Seite nach diesem Patch keine Daten mehr lädt,
-- prüfe ZUERST: ist status_index.html wirklich auf Build 2026-05-15T2245?
-- Wenn nein → bitte erst die HTML deployen, NICHT die Policy zurückrollen.
-- 
-- Notfall-Rollback (nur wenn der Patch wirklich Probleme macht):
-- 
-- CREATE POLICY csc_bewerbungen_select_self_token
--   ON csc_bewerbungen
--   FOR SELECT
--   TO anon, authenticated
--   USING (bewerber_token IS NOT NULL);
-- ============================================================================

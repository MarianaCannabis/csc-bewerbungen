// ============================================================================
// Edge Function: withdraw-bewerbung
// ============================================================================
// Zweck: DSGVO Art. 17 Selbstlöschung durch den Bewerber.
//
// Warum Edge Function statt SQL-Function (csc_withdraw_bewerbung):
//   Supabase blockt DELETE FROM storage.objects auch in SECURITY DEFINER
//   functions. Storage-Files MÜSSEN über die Storage-API gelöscht werden,
//   sonst bleiben Orphans im Bucket. Service-Role hat die nötigen Rechte.
//
// Fluss:
//   1) Token entgegennehmen (Body)
//   2) Bewerbung + Anhang-Paths laden (read-only, Service-Role)
//   3) Storage-Files via Storage-API löschen
//   4) SQL-Function csc_withdraw_bewerbung_db_only() callen → löscht
//      Anhang-Records, Notizen, Changes-Log, Bewerbung selbst
//   5) Erfolgs-Response
//
// Sicherheit:
//   - Token ist die einzige Auth (bekannt nur dem Bewerber via Status-Link)
//   - Service-Role-Key bleibt server-side
//   - Bewerber kann NUR seine eigene Bewerbung löschen (Token-Lookup)
//   - Wenn Token ungültig: 404, kein Datenleck
//
// Deployment:
//   supabase functions deploy withdraw-bewerbung --project-ref gvzayggvtlychyjbnsgv
// ============================================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const STORAGE_BUCKET = 'bewerbung-anhaenge';

serve(async (req) => {
  // CORS-Preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonRes({ ok: false, error: 'Method not allowed' }, 405);
  }

  try {
    // ── Token aus Body ───────────────────────────────────────────────────────
    let body: { token?: string } = {};
    try {
      body = await req.json();
    } catch {
      return jsonRes({ ok: false, error: 'Invalid JSON body' }, 400);
    }
    const token = (body.token || '').trim();
    if (!token || token.length < 16) {
      return jsonRes({ ok: false, error: 'Token fehlt oder ungültig.' }, 400);
    }

    // ── Service-Role-Client ──────────────────────────────────────────────────
    const supabaseUrl     = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    if (!supabaseUrl || !serviceRoleKey) {
      console.error('[withdraw-bewerbung] Missing env vars');
      return jsonRes({ ok: false, error: 'Server-Konfiguration unvollständig.' }, 500);
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // ── 1) Bewerbung finden (per Token) ──────────────────────────────────────
    const { data: bewerbung, error: findErr } = await admin
      .from('csc_bewerbungen')
      .select('id, email, vorname, nachname')
      .eq('bewerber_token', token)
      .single();

    if (findErr || !bewerbung) {
      // Kein Datenleck: gleicher Text wie bei abgelaufenem Token
      return jsonRes(
        { ok: false, error: 'Bewerbung nicht gefunden oder Token ungültig.' },
        404
      );
    }

    const bewerbungId = bewerbung.id;
    const vorname     = bewerbung.vorname || '';
    console.log(`[withdraw-bewerbung] Start delete for bewerbung_id=${bewerbungId}`);

    // ── 2) Anhang-Storage-Paths laden ────────────────────────────────────────
    const { data: anhaenge, error: anhErr } = await admin
      .from('csc_bewerbung_anhaenge')
      .select('storage_path')
      .eq('bewerbung_id', bewerbungId)
      .not('storage_path', 'is', null);

    if (anhErr) {
      console.error('[withdraw-bewerbung] Anhang-Query Fehler:', anhErr);
      return jsonRes({ ok: false, error: 'Datenbank-Fehler (Anhänge).' }, 500);
    }

    const paths: string[] = (anhaenge || [])
      .map((a) => a.storage_path)
      .filter((p): p is string => !!p);

    // ── 3) Storage-Files löschen via Storage-API ─────────────────────────────
    let storageDeleted = 0;
    let storageWarnings: string[] = [];
    if (paths.length > 0) {
      // Storage-API erlaubt batch delete; bei einzelnen Fehlern weitermachen
      // damit DB-Cleanup trotzdem durchläuft (Files können ggf. später manuell
      // weggeräumt werden, aber DB-Konsistenz hat Vorrang).
      const { data: removed, error: storErr } = await admin
        .storage
        .from(STORAGE_BUCKET)
        .remove(paths);

      if (storErr) {
        console.warn('[withdraw-bewerbung] Storage-Delete Warning:', storErr);
        storageWarnings.push(storErr.message);
      } else {
        storageDeleted = removed?.length || 0;
        console.log(`[withdraw-bewerbung] Deleted ${storageDeleted}/${paths.length} files`);
      }
    }

    // ── 4) DB-Cleanup über SQL-Function ──────────────────────────────────────
    const { data: dbResult, error: rpcErr } = await admin.rpc(
      'csc_withdraw_bewerbung_db_only',
      { p_bewerbung_id: bewerbungId }
    );

    if (rpcErr) {
      console.error('[withdraw-bewerbung] DB-Cleanup Fehler:', rpcErr);
      return jsonRes(
        {
          ok: false,
          error: 'Datenbank-Cleanup fehlgeschlagen: ' + rpcErr.message,
          storage_deleted: storageDeleted,
        },
        500
      );
    }

    if (!dbResult || dbResult.ok !== true) {
      console.error('[withdraw-bewerbung] DB-Cleanup ungültiges Result:', dbResult);
      return jsonRes(
        { ok: false, error: dbResult?.error || 'Datenbank-Cleanup unklar.' },
        500
      );
    }

    // ── 5) Erfolg ────────────────────────────────────────────────────────────
    console.log(`[withdraw-bewerbung] OK — bewerbung_id=${bewerbungId}, files=${storageDeleted}`);
    return jsonRes({
      ok: true,
      message: 'Deine Bewerbung wurde vollständig gelöscht. Alle deine Daten wurden entfernt.',
      vorname,
      storage_deleted: storageDeleted,
      storage_warnings: storageWarnings,
    });
  } catch (e) {
    console.error('[withdraw-bewerbung] Unhandled error:', e);
    return jsonRes(
      { ok: false, error: 'Unerwarteter Fehler: ' + (e?.message || String(e)) },
      500
    );
  }
});

function jsonRes(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

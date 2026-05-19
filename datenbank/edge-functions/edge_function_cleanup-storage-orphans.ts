// ============================================================================
// Edge Function: cleanup-storage-orphans
// ============================================================================
// Zweck: Storage-Files entfernen, die KEINEN DB-Eintrag in 
//        csc_bewerbung_anhaenge haben.
//
// Hintergrund: Vor dem Fix von Bug 1 (15.05.2026) hat die alte SQL-Function
// csc_withdraw_bewerbung() die DB-Records gelöscht aber Storage-Files
// stehen lassen (weil DELETE FROM storage.objects blockte). Resultat:
// 13 Orphan-Files im Bucket — DSGVO-Verstoß (Daten ohne Rechtsgrundlage).
//
// Sicherheit:
//   - Nur via Service-Role aufrufbar (über Admin-Token im Header)
//   - DRY-RUN per default — gibt nur die Liste zurück ohne zu löschen
//   - Erst bei body.confirm = true wird tatsächlich gelöscht
//   - Bewerbung-IDs werden mit csc_bewerbungen abgeglichen — falls eine
//     Bewerbung existiert aber der Anhang-DB-Record fehlt, könnte das ein
//     Sonderfall sein → Vorsicht, nicht löschen, dem User zeigen
//
// Aufruf:
//   DRY-RUN (zeigt nur):
//     curl -X POST https://gvzayggvtlychyjbnsgv.supabase.co/functions/v1/cleanup-storage-orphans \
//       -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
//       -H "Content-Type: application/json" \
//       -H "x-admin-token: $CLEANUP_ADMIN_TOKEN" \
//       -d '{}'
//
//   LÖSCHUNG ausführen:
//     curl ... -d '{"confirm": true}'
//
// Deployment:
//   supabase functions deploy cleanup-storage-orphans --project-ref gvzayggvtlychyjbnsgv
//
// Environment-Vars die gesetzt sein müssen:
//   - SUPABASE_URL                 (auto)
//   - SUPABASE_SERVICE_ROLE_KEY    (auto)
//   - CLEANUP_ADMIN_TOKEN          (manuell setzen: ein langes Random-Secret)
// ============================================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-admin-token',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const STORAGE_BUCKET = 'bewerbung-anhaenge';

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonRes({ ok: false, error: 'Method not allowed' }, 405);
  }

  try {
    // ── Admin-Token-Check ─────────────────────────────────────────────────
    const adminToken      = req.headers.get('x-admin-token');
    const expectedToken   = Deno.env.get('CLEANUP_ADMIN_TOKEN');
    if (!expectedToken) {
      return jsonRes({ ok: false, error: 'CLEANUP_ADMIN_TOKEN nicht konfiguriert' }, 500);
    }
    if (adminToken !== expectedToken) {
      return jsonRes({ ok: false, error: 'Unauthorized' }, 401);
    }

    // ── Body parsen ────────────────────────────────────────────────────────
    let body: { confirm?: boolean } = {};
    try { body = await req.json(); } catch { body = {}; }
    const confirmDelete = body.confirm === true;

    // ── Service-Role-Client ────────────────────────────────────────────────
    const supabaseUrl    = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // ── 1) ALLE Files im Bucket listen (rekursiv) ──────────────────────────
    // Storage.list ist NICHT rekursiv — wir müssen pro Bewerbungs-Ordner listen
    // Erst alle "Ordner" (= bewerbung_ids) auf Root-Ebene holen
    const allFiles: { name: string; bewerbungId: string }[] = [];

    const { data: rootEntries, error: rootErr } = await admin
      .storage
      .from(STORAGE_BUCKET)
      .list('', { limit: 1000 });

    if (rootErr) {
      return jsonRes({ ok: false, error: 'List failed: ' + rootErr.message }, 500);
    }

    // Pro Bewerbungs-Ordner die Files listen
    for (const entry of rootEntries || []) {
      // Ordner haben id=null, Files haben id=<uuid>
      const isFolder = entry.id === null;
      if (isFolder) {
        const { data: files } = await admin
          .storage
          .from(STORAGE_BUCKET)
          .list(entry.name, { limit: 1000 });
        for (const f of files || []) {
          if (f.id !== null) {
            // Es ist ein File (kein weiterer Sub-Ordner)
            allFiles.push({
              name: `${entry.name}/${f.name}`,
              bewerbungId: entry.name,
            });
          }
        }
      } else {
        // File direkt auf Root-Ebene — sollte nicht vorkommen, aber falls
        allFiles.push({ name: entry.name, bewerbungId: '' });
      }
    }

    console.log(`[cleanup] Gefunden: ${allFiles.length} Files im Bucket`);

    // ── 2) Pfade gegen csc_bewerbung_anhaenge abgleichen ───────────────────
    const allPaths = allFiles.map((f) => f.name);
    const { data: dbAnhaenge, error: anhErr } = await admin
      .from('csc_bewerbung_anhaenge')
      .select('storage_path')
      .in('storage_path', allPaths);

    if (anhErr) {
      return jsonRes({ ok: false, error: 'DB-Query failed: ' + anhErr.message }, 500);
    }

    const knownPaths = new Set((dbAnhaenge || []).map((a) => a.storage_path));
    const orphans = allFiles.filter((f) => !knownPaths.has(f.name));

    console.log(`[cleanup] Orphans: ${orphans.length}`);

    // ── 3) Zusätzlicher Schutz-Check: existiert die Bewerbung noch?  
    //     Falls JA, aber Anhang-Record fehlt → seltsam, NICHT löschen
    const orphanBewerbungIds = [...new Set(orphans.map((o) => o.bewerbungId).filter(Boolean))];
    const { data: existingBewerbungen } = await admin
      .from('csc_bewerbungen')
      .select('id')
      .in('id', orphanBewerbungIds);

    const existingIds = new Set((existingBewerbungen || []).map((b) => b.id));
    
    const safeOrphans       = orphans.filter((o) => !existingIds.has(o.bewerbungId));
    const suspiciousOrphans = orphans.filter((o) => existingIds.has(o.bewerbungId));

    // ── 4) DRY-RUN oder echte Löschung ─────────────────────────────────────
    if (!confirmDelete) {
      return jsonRes({
        ok: true,
        mode: 'dry-run',
        message: 'Nichts gelöscht. Setze "confirm": true um die safe_orphans zu löschen.',
        total_files:       allFiles.length,
        db_records:        knownPaths.size,
        orphans_total:     orphans.length,
        safe_orphans:      safeOrphans.length,
        suspicious_orphans: suspiciousOrphans.length,
        safe_orphans_list: safeOrphans.map((o) => o.name),
        suspicious_list:    suspiciousOrphans.map((o) => o.name),
      });
    }

    // Echte Löschung — nur safe_orphans
    if (safeOrphans.length === 0) {
      return jsonRes({
        ok: true,
        mode: 'delete',
        message: 'Keine sicher löschbaren Orphans gefunden.',
        deleted: 0,
      });
    }

    const pathsToDelete = safeOrphans.map((o) => o.name);
    const { data: removed, error: rmErr } = await admin
      .storage
      .from(STORAGE_BUCKET)
      .remove(pathsToDelete);

    if (rmErr) {
      return jsonRes({ ok: false, error: 'Delete failed: ' + rmErr.message }, 500);
    }

    console.log(`[cleanup] Gelöscht: ${removed?.length || 0} Files`);

    // Migration-Log-Eintrag erstellen
    await admin.from('csc_migration_log').insert({
      migration_id: `2026-05-15_storage_orphan_cleanup_${Date.now()}`,
      beschreibung: `Storage-Orphan-Cleanup: ${removed?.length || 0} Files ohne DB-Eintrag entfernt`,
      autor: 'edge-function:cleanup-storage-orphans',
      notizen: `Gelöschte Pfade: ${pathsToDelete.join(', ')}`,
    });

    return jsonRes({
      ok: true,
      mode: 'delete',
      deleted: removed?.length || 0,
      deleted_paths: pathsToDelete,
      suspicious_skipped: suspiciousOrphans.length,
      suspicious_list: suspiciousOrphans.map((o) => o.name),
    });
  } catch (e) {
    console.error('[cleanup-storage-orphans]', e);
    return jsonRes({ ok: false, error: 'Unhandled: ' + (e?.message || String(e)) }, 500);
  }
});

function jsonRes(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

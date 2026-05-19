# K3 — Fix-Plan: `send-status-email` ohne Webhook-Secret

**Status:** Plan, noch nicht umgesetzt. Datei-Änderungen, Env-Variable und
Webhook-Umkonfiguration stehen unten als drei voneinander getrennte Schritte.

---

## 1. Was die Function heute tut — Ist-Zustand

Datei: `datenbank/edge-functions/edge_function_send-status-email.ts`

**Aufrufweg (laut Datei-Kommentar Z. 7-14 und Doku-Erwähnung in `feature_*.sql`):**
Wird über einen **Supabase-DB-Webhook** auf `csc_bewerbungen` (UPDATE-Trigger)
aufgerufen. Erwartetes Payload-Format:

```json
{
  "type": "UPDATE",
  "table": "csc_bewerbungen",
  "schema": "public",
  "record":     { ...neue Zeile inkl. status, email, vorname, verein_id, bewerber_token, id, eingestellt_details... },
  "old_record": { ...vorherige Zeile... }
}
```

**Was die Function aus dem Payload zieht (Z. 98-100):**
```ts
const payload    = await req.json();
const record     = payload.record     || payload.new || payload;
const oldRecord  = payload.old_record || payload.old || {};
```
→ Es gibt keine Validierung, dass der Request wirklich vom DB-Webhook kommt.
   Jeder POST mit passendem JSON-Body wird verarbeitet.

**CORS-Konfiguration (Z. 87-94 und Z. 193):**
```ts
'Access-Control-Allow-Origin': '*',
'Access-Control-Allow-Methods': 'POST',
'Access-Control-Allow-Headers': 'Content-Type, Authorization',
```
→ Wildcard-Origin. Aus einem Browser-Kontext aufrufbar, kein
   Server-zu-Server-Lock.

**Was die Function aus dem Payload macht:**
- liest `record.verein_id` und holt mit Service-Role den Verein-Namen aus
  `csc_vereine` (Z. 130-134)
- baut eine Status-Mail (Subject + HTML + Plain-Text) basierend auf
  `record.vorname`, `record.nachname`, `record.email`, `record.status`,
  `record.eingestellt_details`, `record.bewerber_token`
- ruft `transporter.sendMail` über SMTP-Provider (Standard `smtp.ionos.de`,
  Z. 168-182) mit `from = fromName/fromEmail`, `to = record.email`,
  `replyTo = vereinContact || replyToEmail`.

**Was ein Angreifer daraus machen kann** (sofern er auch nur den Anon-Key
hat — der steht öffentlich im Frontend-Code):

```bash
curl -X POST https://<projectref>.supabase.co/functions/v1/send-status-email \
  -H "Authorization: Bearer <ANON_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "record":     { "status": "angenommen",
                    "email": "opfer@evil.tld",
                    "vorname": "Liebe Kundin",
                    "nachname": "X",
                    "verein_id": "<UUID eines echten Vereins>",
                    "bewerber_token": "irgendwas",
                    "id": "00000000-0000-0000-0000-000000000000",
                    "eingestellt_details": [{"rolle":"ausgabe","vertrag":"minijob"}] },
    "old_record": { "status": "eingegangen" }
  }'
```

Resultat: Mariana-Cannabis-gebrandete „Willkommen bei <echter Verein>"-Mail
an `opfer@evil.tld`, signiert mit der `csc...@cscsdeutschland.de`-Absender-
Adresse — also ein perfekt aussehender Phishing-Träger. Kein Brute-Force,
kein Spoofing nötig.

---

## 2. Was fehlt — drei Lücken

| Lücke | Konsequenz |
|---|---|
| Kein Shared-Secret-Check zwischen DB-Webhook und Function | Function kann von jedem mit Anon-Key aufgerufen werden, nicht nur vom DB-Webhook |
| `Access-Control-Allow-Origin: '*'` | Direkt aus dem Browser eines beliebigen Origins aufrufbar — erweitert die Angriffsfläche unnötig (Webhook ist Server-zu-Server) |
| Kein Origin/Caller-Logging zur Diagnose | Wenn doch missbraucht, hat man im Edge-Function-Log keine Spur, wer es ausgelöst hat |

Genau dasselbe Muster macht `cleanup-storage-orphans.ts` schon richtig (Z. 60-68):
einen `x-admin-token`-Header gegen `Deno.env.get('CLEANUP_ADMIN_TOKEN')` prüfen.
Wir spiegeln das Pattern.

---

## 3. Fix — was sich konkret ändert

### 3a. Env-Variable in Supabase setzen (Dashboard → Edge Functions → Settings)

Eine neue Secret-Variable:

```
WEBHOOK_SECRET = <ca. 48 Zeichen, Random>
```

Erzeugen z. B. mit `openssl rand -hex 24` oder `python -c "import secrets; print(secrets.token_hex(24))"`.
Den Wert sicher ablegen (Passwort-Manager) — er wird auch im DB-Webhook
benötigt (Schritt 3c).

### 3b. Code-Änderung in `edge_function_send-status-email.ts`

**Stelle 1 — CORS-Header verengen (Z. 86-94 und Z. 193)**

Diff-Vorschlag:

```diff
 serve(async (req: Request) => {
+  // Server-zu-Server-Function — kein Browser-Aufruf erwartet. CORS minimal.
+  const corsHeaders = {
+    'Access-Control-Allow-Origin': 'null',
+    'Access-Control-Allow-Methods': 'POST',
+    'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-webhook-secret',
+  };
   if (req.method === 'OPTIONS') {
-    return new Response('ok', {
-      headers: {
-        'Access-Control-Allow-Origin': '*',
-        'Access-Control-Allow-Methods': 'POST',
-        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
-      },
-    });
+    return new Response('ok', { headers: corsHeaders });
   }
```

Und am Erfolgs-Response (Z. 193):
```diff
-      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
+      headers: { 'Content-Type': 'application/json', ...corsHeaders },
```

**Stelle 2 — Webhook-Secret-Check direkt nach OPTIONS (vor dem `try`)**

```diff
   if (req.method === 'OPTIONS') {
     return new Response('ok', { headers: corsHeaders });
   }
+
+  // ── Webhook-Secret-Check ───────────────────────────────────────────────
+  // Die Function wird ausschliesslich vom Supabase-DB-Webhook auf
+  // csc_bewerbungen aufgerufen. Ohne Secret-Check koennte jeder mit
+  // Anon-Key aus der oeffentlichen Frontend-Konfiguration eine beliebige
+  // Status-Mail mit echtem Mariana-Branding versenden lassen
+  // (Phishing-Vektor, Sicherheits-Review Befund K3).
+  const expectedSecret = Deno.env.get('WEBHOOK_SECRET');
+  if (!expectedSecret) {
+    console.error('[send-status-email] WEBHOOK_SECRET nicht konfiguriert');
+    return new Response(JSON.stringify({ error: 'Server-Konfiguration unvollstaendig' }), {
+      status: 500,
+      headers: { 'Content-Type': 'application/json', ...corsHeaders },
+    });
+  }
+  const providedSecret = req.headers.get('x-webhook-secret');
+  if (providedSecret !== expectedSecret) {
+    console.warn('[send-status-email] Unauthorized — fehlender oder falscher x-webhook-secret');
+    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
+      status: 401,
+      headers: { 'Content-Type': 'application/json', ...corsHeaders },
+    });
+  }
+
   try {
```

**Stelle 3 — Logging tighten (optional, parallel zu N4)**

Z. 184 loggt heute `record.email` und `vereinName` im Klartext:
```ts
console.log(`Status-Mail an ${record.email} (Status: ${newStatus}, Verein: ${vereinName})`);
```

Empfehlung: durch eine PII-arme Variante ersetzen:
```ts
console.log(`Status-Mail OK (status=${newStatus}, bewerbung_id=${record.id?.slice(0,8) || '?'})`);
```

Das wäre N4-Vorgriff, kein zwingender Teil von K3 — aber im selben Patch
sinnvoll, weil die Datei sowieso angefasst wird.

### 3c. DB-Webhook in Supabase-Oberfläche umkonfigurieren

Pfad: **Supabase Dashboard → Database → Webhooks → den existierenden Webhook
auf `csc_bewerbungen` öffnen → Edit**.

Im Bereich „HTTP Headers" einen Header hinzufügen:

```
Header Name:  x-webhook-secret
Header Value: <derselbe Wert wie WEBHOOK_SECRET aus Schritt 3a>
```

`Authorization`-Header mit dem Service-Role-Token bleibt unverändert.
Speichern.

### 3d. Deploy-Reihenfolge — wichtig

Reihenfolge ist *nicht* beliebig. Wenn Code zuerst raus geht, ohne dass der
Webhook den Header schon mitschickt → alle automatischen Status-Mails
brechen mit 401 (Bewerber bekommen plötzlich keine Mails mehr).

**Korrekte Sequenz:**

1. `WEBHOOK_SECRET` in Edge-Function-Env setzen (Schritt 3a).
2. DB-Webhook mit dem `x-webhook-secret`-Header konfigurieren (Schritt 3c).
   → Ab jetzt schickt der Webhook den Header mit, die Function ignoriert
     ihn aber noch (alte Version), funktioniert weiter wie bisher.
3. Erst dann die neue Function-Version deployen
   (`supabase functions deploy send-status-email --project-ref gvzayggvtlychyjbnsgv`).
   → Ab jetzt prüft die Function den Header, der Webhook schickt ihn — passt.

**Rollback-Plan:** Wenn nach Schritt 3 etwas brechen sollte —
`supabase functions deploy send-status-email` aus dem alten Stand
(`git`-Stand vor dem Patch) re-deployen. Header am Webhook können bleiben,
schaden nicht.

### 3e. Smoketest nach Deploy

1. Im Dashboard eine Test-Bewerbung manuell auf neuen Status setzen
   (z. B. `in_pruefung`). Im Postfach des Test-Bewerbers muss eine Mail
   ankommen.
2. Aus einem Terminal direkt die Function aufrufen ohne den Secret-Header:
   ```bash
   curl -X POST https://gvzayggvtlychyjbnsgv.supabase.co/functions/v1/send-status-email \
     -H "Authorization: Bearer <ANON_KEY>" \
     -H "Content-Type: application/json" \
     -d '{"record":{"status":"angenommen","email":"test@example.com","vorname":"X","verein_id":"00000000-0000-0000-0000-000000000000"},"old_record":{"status":"eingegangen"}}'
   ```
   Erwartet: HTTP 401, `{"error":"Unauthorized"}`. Wenn 200 → Patch greift
   nicht.
3. Edge-Function-Logs öffnen: für (1) sollte eine OK-Zeile zu sehen sein,
   für (2) eine `Unauthorized`-Warnung.

---

## 4. Spätere Folge-Punkte (nicht Teil von K3, aber thematisch nah)

- Die anderen drei Edge Functions — `withdraw-bewerbung`, `get-bewerbung-status`,
  `send-bewerbung-email` (letztere beide nicht im Repo, siehe `OFFENE_PUNKTE.md`
  Punkt 3) — auf dasselbe Muster prüfen. `withdraw-bewerbung` ist
  token-validiert (eigene Authentifizierung), die zwei nicht-versionierten
  müssten gezogen und einzeln bewertet werden.
- N4: Logging PII reduzieren (siehe Stelle 3 oben, optional gleich
  miterledigen).
- N2: CORS-Hardening — `send-status-email` ist der einzige Webhook-Empfänger
  hier, die anderen Functions sind teils legitim aus dem Browser aufrufbar
  und sollten in einem eigenen Pass behandelt werden.

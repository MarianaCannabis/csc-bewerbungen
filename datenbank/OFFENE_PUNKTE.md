# Offene Punkte — Datenbank-Hardening

Diese Datei sammelt kleinere Folge-Arbeiten am DB-Layer, die aus den
Hardening-Runden vom Mai 2026 übrig geblieben sind. Reihenfolge ohne
Priorisierung — jeder Punkt ist eigenständig adressierbar.

---

## 1. NK2 — `csc_auto_promote_admin` braucht `SET search_path = public`

**Befund:** Im Live-Audit am 19.05.2026 hatten 11 SECURITY-DEFINER-Funktionen
keine `proconfig`-Eintragung (also kein gepinntes `search_path`). Die
betreffenden Funktionen werden in einer separaten NK2-Migration komplett
nachgehärtet — `csc_auto_promote_admin` ist hier nur deshalb gesondert
erwähnt, weil dazu ein zweiter Punkt gehört (siehe 2).

**Fix:**
```sql
ALTER FUNCTION public.csc_auto_promote_admin() SET search_path = public;
```

Signatur ggf. vorher per
`SELECT pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname = 'csc_auto_promote_admin'`
gegenchecken.

---

## 2. Cleanup — `csc_auto_promote_admin` enthält 9 hartkodierte Admin-Mails

**Befund:** Die Funktion `csc_auto_promote_admin()` (Trigger-Body an
`auth.users`) entscheidet über die Vergabe der `hauptverein_admin`-Rolle
beim erstmaligen Login. Sie prüft die E-Mail-Adresse gegen eine
**hartkodierte Liste von 9 Adressen** — parallel zur dafür eigentlich
vorgesehenen Tabelle `csc_hauptverein_admin_whitelist`.

**Warum problematisch:**
- Zwei Quellen der Wahrheit für „wer ist Admin?" — Drift unvermeidlich.
- Änderungen an der Admin-Liste erfordern einen Code-Deploy der Funktion
  statt eines simplen Tabellen-INSERTs.
- Die Tabelle `csc_hauptverein_admin_whitelist` suggeriert fälschlich, dass
  sie die einzige Stelle ist, an der man Admins pflegt.

**Vorschlag:** Die Funktion umbauen, sodass sie ausschließlich gegen
`csc_hauptverein_admin_whitelist` prüft. Hartkodierte Liste entfernen,
fehlende Adressen vorher in die Tabelle migrieren. Idealerweise im gleichen
Patch wie Punkt 1 — die Funktion wird ohnehin angefasst.

---

## 3. Edge-Function-Sourcen versionieren

**Befund:** Drei produktiv laufende Edge Functions haben keinen versionierten
Quellcode im Repo — **Verhalten nicht statisch prüfbar**:

- `get-bewerbung-status` — Status-Seite (anon ruft sie über `sb.functions.invoke`)
- `send-bewerbung-email` — Eingangsbestätigung an Bewerber
- `log-error` — JS-Fehler-Logging aus Bewerbungsbogen und Dashboard

Im Repo liegen nur `withdraw-bewerbung`, `send-status-email` und
`cleanup-storage-orphans` (`datenbank/edge-functions/`). Bestätigt durch
vollständige Repo-Datei-Enumeration am 19.05.2026 (insgesamt drei `.ts`-
Dateien im Projekt, keine davon `get-bewerbung-status`, kein Ordner mit
einer `index.ts`-Datei dieses Namens).

**Warum problematisch:** Beim NK3-Hardening (19.05.2026) brach
`get-bewerbung-status` mit "non-2xx status code", weil in ihrer internen
Aufruf-Kette `csc_check_email_whitelist` im anon-Kontext landete und das
EXECUTE-Recht nur über PUBLIC hatte. Ohne den Source konnte die Aufruf-Kette
nur vermutet werden — der Fix (`GRANT EXECUTE … TO anon`) war zwingend
Trial-and-Error statt einer gezielten Code-Korrektur. Bei künftigen
DB-Patches (NK2, View-Hardening, RLS-Änderungen) droht dasselbe Muster.

**Was zu tun ist:**
```bash
supabase functions download get-bewerbung-status --project-ref gvzayggvtlychyjbnsgv
supabase functions download send-bewerbung-email --project-ref gvzayggvtlychyjbnsgv
supabase functions download log-error            --project-ref gvzayggvtlychyjbnsgv
```
Die drei Files in `datenbank/edge-functions/` ablegen (Konvention:
`edge_function_<name>.ts` wie die bestehenden). Bei `get-bewerbung-status`
zusätzlich die Aufruf-Kette analysieren und idealerweise die ungewollte
anon-Vermittlung von `csc_check_email_whitelist` schließen — danach kann
das anon-GRANT auf diese Funktion (siehe `hardening_anon_executes.sql`)
wieder raus.

Ab da das Repo als Single Source of Truth für Edge Functions führen
(`supabase functions deploy --project-ref … <name>` aus den committed Files).

---

## 4. Datenqualität — beschädigter Anhang `0-sonstiges.pdf`

**Befund:** Beim K1-Smoketest am 19.05.2026 zeigte sich, dass mindestens
eine im Storage-Bucket `bewerbung-anhaenge` liegende Datei (Pfad-Endung
`0-sonstiges.pdf`, vom Bewerber als „Mariana_Bewerbungs_Handbuch.pdf"
hochgeladen) als defekt geliefert wird — pdf.js meldet **"Invalid PDF
structure"**, der Download „hängt" (Browser versucht inline-Anzeige der
korrupten Bytes statt Download, weil `a.download` cross-origin ignoriert
wird). Andere PDFs derselben Bewerbung / anderer Bewerbungen funktionieren
normal — also kein systematisches Storage- oder Berechtigungsproblem.

**Kein Sicherheitsproblem**, aber Datenqualitäts-Hinweis: der Bewerbungsbogen
akzeptiert offenbar Uploads, deren Inhalt nicht zur Endung passt oder die
während des Uploads abgebrochen wurden (0 Byte oder abgeschnitten).

**Empfohlener Folge-Check am Bewerbungsbogen** (`csc-bewerbungen/index.html`,
Submit-Pfad ca. Z. 6233-6271):

- **Mindest-Dateigröße:** vor dem Storage-Upload prüfen, ob `a.file.size > 0`
  ist (entdeckt abgebrochene Uploads / leere Dateien).
- **MIME-Type-Check:** beim Upload wird zwar `contentType: a.mime` mitgegeben,
  aber `a.mime` ist die Browser-Vermutung aus dem File-Picker (Endung-basiert),
  nicht eine echte Magic-Byte-Prüfung. Eine simple Header-Inspektion (erste
  4 Bytes lesen, `%PDF` für PDF / `\xFF\xD8\xFF` für JPEG / `\x89PNG` für PNG)
  würde umbenannte Dateien aussortieren.
- **Server-Seite:** Storage akzeptiert via Bucket-Settings einen
  `allowed_mime_types`-Filter (in `storage.buckets`). Falls dort heute leer:
  auf `["application/pdf","image/jpeg","image/png","image/heic"]` setzen.
  Verhindert wenigstens, dass beim Upload überhaupt non-PDF unter `.pdf`-Pfad
  landet (Bucket prüft den vom Client gemeldeten MIME).

Die korrupte Datei selbst kann der Vorstand über den Lösch-Button im
Dashboard entfernen — der Anhang ist für die Bewerbung ohnehin wertlos.

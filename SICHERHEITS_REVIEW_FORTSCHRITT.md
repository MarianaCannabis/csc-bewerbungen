# Sicherheits-Review CSC-Bewerbungssystem — Fortschritt

**Letzter Stand:** 19.05.2026

Status-Übersicht der Befunde aus dem Sicherheits-Review. Detailbefunde stehen
in den jeweiligen Hardening-Skripten unter `datenbank/` bzw. im Diff der
`csc-bewerbungen/dashboard/index.html`. Offene Folge-Arbeiten in
`datenbank/OFFENE_PUNKTE.md`. Konkreter Fix-Plan für den nächsten kritischen
Punkt in `datenbank/K3_PLAN.md`.

---

## Datenbank-Layer — abgeschlossen

| Befund | Maßnahme | Status |
|---|---|---|
| **NK1** — anon hatte ALL PRIVILEGES auf 8 sensiblen `csc_*`-Tabellen (u. a. `csc_vertragsdaten`, `csc_hauptverein_admin_whitelist`) | `datenbank/hardening_anon_grants_2.sql` — REVOKE ALL, GRANT SELECT auf `csc_vereine_public` zurück | **erledigt, live verifiziert** |
| **NK3** — anon konnte ~30 Funktionen über PUBLIC-Default aufrufen | `datenbank/hardening_anon_executes.sql` — REVOKE EXECUTE FROM PUBLIC + anon, gezielte Whitelist mit 5 Funktionen | **erledigt, live verifiziert** (anon hat final EXECUTE auf `csc_bewerbung_exists`, `csc_check_email_whitelist`, `csc_check_login_allowed`, `get_vertragsdaten_status`, `save_vertragsdaten`) |
| **NK2** — 11 SECURITY-DEFINER-Funktionen ohne `SET search_path` | `datenbank/hardening_search_path.sql` — 11× ALTER FUNCTION; Quelldatei-Patch in `fix_withdraw_bewerbung.sql:106` | **erledigt, live verifiziert** (Kontroll-Abfrage: 0 Funktionen ohne gepinnten search_path) |

Zwischenfälle während des DB-Blocks (alle behoben):
- Dashboard-Login brach nach PUBLIC-REVOKE → `csc_check_login_allowed` an anon zurückgegrantet.
- Status-Seite brach nach PUBLIC-REVOKE → `csc_check_email_whitelist()` (parameterlos, nicht `(text)`) an anon zurückgegrantet.
- Vertragsdaten-Status fehlte zwischenzeitlich → GRANT-Statements mit korrekten Signaturen nachgezogen.

---

## Frontend-Layer

| Befund | Maßnahme | Status |
|---|---|---|
| **K2** — XSS via JSONB-Keys in `b.sprachen`/`b.soft_skills` (Dashboard, Z. 2759/2765) | Vier `escapeHtml`-Wraps + `Number()`-Cast für Score-Anzeige | **erledigt, deployed, browser-verifiziert** |
| **K1** — XSS via Dateiname in `onclick`-Attributen der Anhang-Buttons (Dashboard, Z. 3115-3125) | `data-action`-basierte Event-Delegation am `.anhang-list`-Container, `attachAnhangActions(...)` als zentraler Handler | **erledigt, deployed, browser-verifiziert** (5 Smoketests grün; PDF-Fehler bei einer Datei war defekter Upload, nicht K1-Regression — siehe `OFFENE_PUNKTE.md` Punkt 4) |
| **M3** — Linkify-Regex in `plainToHtml` zu permissiv, eigene 3-Zeichen-Escape umgeht zentrale `escapeHtml`, `srcdoc`-Iframe ohne Sandbox (Dashboard, Z. 5734-5741 und 5891) | Lokales Escape durch zentrales `escapeHtml` ersetzt + Regex auf `[^\s<"]+` verengt + `sandbox=""` am Preview-Iframe + Reihenfolge-Kommentar | **deployed (am 19.05.2026 per Volldiff-Vergleich gegen Live-URL bestätigt: byte-genau identisch), Browser-Smoketest des Mail-Preview-Iframes formell noch offen** |

---

## Offene Restliste — Roadmap

Sortiert nach Schweregrad. Aufwand: **klein** = ≤30 min, **mittel** = 1–3 h,
**groß** = halber Tag oder mehr (Schema-Änderungen, Architektur-Eingriff).

### Kritisch

| Befund | Problem | Lösungsansatz | Schicht | Aufwand |
|---|---|---|---|---|
| **K3** — `send-status-email` ohne Webhook-Secret | Edge Function trusted den Request-Body komplett, CORS `*` → jeder mit Anon-Key kann Phishing-Mail mit echtem Mariana-Branding an beliebige Adresse auslösen (Mail-Relay-Vektor) | Shared-Secret-Pattern analog `cleanup-storage-orphans`: `WEBHOOK_SECRET` als Env-Var, `x-webhook-secret`-Header am DB-Webhook setzen, in der Function gegenprüfen | Edge Function | **klein** — fertiger Plan steht in `datenbank/K3_PLAN.md` |

### Mittel

| Befund | Problem | Lösungsansatz | Schicht | Aufwand |
|---|---|---|---|---|
| **M1** — anon-Tabellen-GRANT auf `csc_bewerbungen` ist spaltenweit | Anon darf beim INSERT ALLE Spalten setzen — `status`, `score_gesamt`, `vorstand_notiz`, `tags`, `bewerber_token` etc. Kein Datenleak, aber Datenintegrität: ein Bot kann sich selbst als „angenommen, score 100, vorstand_notiz='unbedingt einstellen!'" einschleusen | Variante A: Spalten-GRANT statt Tabellen-GRANT — `GRANT INSERT (verein_id, vorname, …) ON csc_bewerbungen TO anon`. Variante B: SECURITY-DEFINER-`csc_submit_bewerbung(jsonb)` mit Whitelist im Function-Body, Anon verliert direkten INSERT | DB | **mittel** (Variante A in 30 min, Variante B in 2 h plus Test) |
| **M2** — `csc_withdraw_bewerbung(text)`-Stub ohne `SET search_path` | War im ursprünglichen Review als eigener Mittel-Befund gelistet | **bereits erledigt** als Teil von NK2 (Quelldatei-Patch in `fix_withdraw_bewerbung.sql:106` plus ALTER in `hardening_search_path.sql`) | — | — |
| **M4** — Storage-INSERT-Policy ohne Bewerbungs-Bezug | `bewerbung-anhaenge`-Bucket akzeptiert anon-Uploads ohne Prüfung, ob eine zugehörige Bewerbung existiert oder ob die Datei kategorisiert ist. Risiko: Speicher-Abuse (kein Rate-Limit pro IP, kein File-Size-Limit) | (a) `file_size_limit` und `allowed_mime_types` auf `storage.buckets` setzen, (b) `cleanup-storage-orphans` als pg_cron-Job einplanen, (c) Edge-Function-basierter Upload mit Rate-Limit als Folge-Ausbaustufe | DB + Storage-Bucket-Settings | **klein** (a+b) / **groß** (c) |
| **M5** — `bewerber_token`-Lebenszyklus | Einmal erzeugt, nie rotiert, steht im Klartext in der Status-URL → Browser-Verlauf, Referer-Header, Mail-Provider-Logs. Ein Token erlaubt Status lesen + Vertragsdaten schreiben + DSGVO-Löschung | Schritt 1 (sofort, klein): `<meta name="referrer" content="no-referrer">` in `status/index.html`. Schritt 2 (mittel): zweiter, kurzlebiger Token für `save_vertragsdaten` nach Status-Wechsel auf „angenommen". Schritt 3 (groß): TTL auf den Status-Token (z. B. 12 Monate ab `eingegangen_am`) | Frontend + DB | **klein** (Schritt 1) bis **groß** (Schritt 3) |
| **M6** — `escapeHtml` in `status/index.html` ohne Single-Quote | Z. 192 escaped nur `<>&"`, nicht `'`. Heute alle Verwendungen in Doppel-quoted-Attribut-Kontext, also kein aktiver Bug — aber Footgun beim nächsten Template-Eingriff | Eine Zeichen-Ergänzung in der Regex-Replace-Map | Frontend | **klein** — wenige Minuten |

### Niedrig

| Befund | Problem | Lösungsansatz | Schicht | Aufwand |
|---|---|---|---|---|
| **N1** — `Math.random()`-Fallback in `generateUUID()` | `csc-bewerbungen/index.html:6323` — bei Browsern ohne `crypto.randomUUID` (heute praktisch keine mehr) fällt der Code auf `Math.random()` zurück, das nicht kryptographisch sicher ist | `throw new Error('Browser nicht unterstützt')` statt Fallback. Evergreen-Browser haben `crypto.randomUUID` seit 2022, alte Browser sollten am Bewerbungsbogen ohnehin scheitern | Frontend | **klein** |
| **N2** — CORS `*` auf allen Edge Functions | `withdraw-bewerbung`, `send-status-email`, `cleanup-storage-orphans` haben `Access-Control-Allow-Origin: *`. Für die Server-zu-Server-Functions (`send-status-email`, `cleanup-storage-orphans`) unnötig weit | `send-status-email`: `null` (siehe K3-Plan). `cleanup-storage-orphans`: ebenfalls `null` oder Origin-Whitelist. `withdraw-bewerbung`: bleibt `*`, weil aus Browser des Bewerbers gerufen | Edge Functions | **klein**, am besten parallel zu K3 |
| **N3** — `Ausgabe-Rechner.html` Z. 2747: `m.type` aus localStorage ohne Escape | `TYPE_LBL[m.type] \|\| m.type` rendert Rohwert in `innerHTML`. Same-Origin-Daten vom Dashboard, nur ausnutzbar wenn Dashboard selbst kompromittiert ist — dann sind die Rechner ohnehin egal | Durch die im File schon vorhandene `escapeImport()`-Funktion schicken — Konsistenz, kein Risikobeitrag | Frontend | **klein** |
| **N4** — Logging mit PII in Edge Functions | `send-status-email.ts:184` loggt `record.email` und `vereinName` im Klartext (Supabase persistiert Edge-Function-Logs → DSGVO-relevant). `withdraw-bewerbung.ts:91, 157` loggt `bewerbung_id` (vertretbar) | `console.log` so umbauen, dass nur UUIDs oder ID-Prefixe geloggt werden, nie Klartext-Mails oder Namen. Im selben Patch wie K3 sinnvoll | Edge Functions | **klein**, parallel zu K3 |
| **N5** — `clientSideToken.substring(0,8)` als „Bewerbungs-ID" angezeigt | Die ersten 8 Zeichen des Auth-Tokens werden dem Bewerber als ID angezeigt (`csc-bewerbungen/index.html`). Funktional harmlos (8 Hex sind nicht als Auth ratebar), aber konzeptuell sauberer wäre eine separate Display-ID (z. B. `id`-UUID-Präfix statt Token) | Eine Zeile umstellen: aus `clientSideToken.substring(0,8)` wird `payload.id.substring(0,8)` | Frontend | **klein** |

### Aus späteren Runden hinzugekommen (siehe `OFFENE_PUNKTE.md`)

| Befund | Priorität |
|---|---|
| **OP-1/2** — `csc_auto_promote_admin` Cleanup: `SET search_path` fehlt (wird über NK2 abgedeckt, falls Funktion nicht inzwischen schon mitgehärtet) + 9 hartkodierte Admin-Mails parallel zur Whitelist-Tabelle | mittel — hängt am Body-Dump der Funktion |
| **OP-3** — Drei produktive Edge Functions ohne versionierten Quellcode (`get-bewerbung-status`, `send-bewerbung-email`, `log-error`) | mittel — vor weiterem Hardening dieser Functions zwingend |
| **OP-4** — Beschädigter Anhang `0-sonstiges.pdf` plus Empfehlung MIME-/Size-Check beim Upload | klein |

---

## Empfohlene nächste Reihenfolge

0. **M3-Smoketest** — Code ist live (per Volldiff bestätigt), nur die einmalige Mail-Modal-Verifikation im Browser steht noch aus. 5 Klicks: Mail-Modal öffnen, Vorlage rendern, URL im Bodytext einbauen, Plain-Text-Toggle, Bewerbungswechsel. Wenn grün → in der Tabelle oben „Browser-Smoketest formell noch offen" streichen.
1. **K3** — Fix-Plan steht in `datenbank/K3_PLAN.md`. Drei Schritte (Env-Var → Webhook-Header → Function-Deploy), Reihenfolge zwingend einzuhalten. Klein, schließt die letzte kritische Lücke.
2. **N4 + N2** im selben Patch mitnehmen — derselbe Edge-Function-File wird ohnehin angefasst.
3. **OP-3** — Edge-Function-Sourcen ins Repo holen. Voraussetzung für sauberes Hardening von `get-bewerbung-status` und `send-bewerbung-email`.
4. **M5 Schritt 1** — Referrer-Policy in `status/index.html`. Eine Zeile, sofort gewonnen.
5. **M1** — anon-INSERT-Spaltenwhitelist oder Submit-Function. Reduziert das Bot-Pollution-Risiko deutlich.
6. **M6, N1, N3, N5** — kleine Frontend-Polishings, sinnvollerweise gebündelt in einem einzigen Patch mit Smoketest.
7. **OP-1/2** — Admin-Promotion-Refactor, sobald der Function-Body-Dump vorliegt.
8. **M4** — Storage-Bucket-Settings + Cron-Job. Tied to Storage-Operations-Reife.
9. **M5 Schritt 2/3** — Token-Modell-Umbau (Architektur-Entscheidung erforderlich).

---

## Rollback-Pfad Dashboard

Da das `csc-review`-Verzeichnis kein Git-Repo ist, liegt eine byte-genaue
Kopie des produktiven Pre-K1-Stands von GitHub Pages unter:

```
csc-bewerbungen/dashboard/index.html.backup-vor-k1k2
```

(Quelle: `https://marianacannabis.github.io/csc-bewerbungen/dashboard/index.html`,
abgerufen vor dem Deploy am 19.05.2026 mit HTTP 200, 435.547 Bytes.)

Falls ein künftiger Patch im Dashboard etwas bricht: Datei zurückkopieren,
über das GitHub-Web-UI in `marianacannabis.github.io/csc-bewerbungen` neu commiten.

Dieses Backup entspricht dem Stand **vor K1+K2** (Original-Frontend ohne
jegliche Sicherheits-Patches).

Ein zweites Backup `csc-bewerbungen/dashboard/index.html.backup-vor-m3`
(am 19.05.2026 von der Live-URL gezogen, 437.658 Bytes, HTTP 200) hält den
**aktuellen Live-Stand inkl. K1+K2+M3** fest. Das ist der Rollback-Punkt für
das nächste Dashboard-Deploy (sobald K3 oder ein anderer Frontend-Patch das
Dashboard wieder anfasst). Nicht löschen.

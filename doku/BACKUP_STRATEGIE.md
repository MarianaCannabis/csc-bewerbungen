# Backup-Strategie · Mariana Bewerbungs-System

Stand: 17.05.2026

## TL;DR

Drei Ebenen:

1. **Supabase Auto-Backups** — täglich, 7 Tage Point-in-Time-Recovery (Pro-Plan). Deckt Datenbank UND Storage ab, liegt aber bei Supabase selbst.
2. **Wöchentliches Off-Site-Backup (Windows)** — das Skript `backup.py` zieht einmal pro Woche einen verschlüsselten Voll-Export (Datenbank + Anhang-Dateien) in eine passwortgeschützte ZIP-Datei. Läuft per Windows-Aufgabenplanung auf Andres PC, Ziel-Ordner in OneDrive. Unabhängig von Supabase.
3. **Manuelle Exports** — vor größeren Releases / Migrationen (siehe Abschnitt 4).

**Recovery-Pfad bei Total-Verlust:** ca. 2–4 Stunden. Wer hat Zugang: Andre (Initial-Admin, Service-Role-Key, Supabase-Owner, Backup-Passwort).

> **Status:** Ebene 2 ist eingerichtet und läuft (Stand 17.05.2026). Die wöchentliche Aufgabe ist in der Windows-Aufgabenplanung als „CSC Backup" aktiv.

---

## 1. Was wird gesichert?

| Komponente | Inhalt | Supabase auto-daily | Wochen-Backup (`backup.py`) |
|---|---|---|---|
| **PostgreSQL-DB** | csc_bewerbungen, csc_bewerbung_anhaenge, csc_bewerbung_notizen, csc_user_profiles, csc_dashboard_user, csc_vereine, csc_mail_log, csc_error_log, csc_bewerbung_changes etc. | ✓ | ✓ (alle `csc_`-Tabellen als JSON) |
| **Storage Bucket `bewerbung-anhaenge`** | hochgeladene Lebensläufe, Zeugnisse | ✓ | ✓ (alle Dateien) |
| **Auth (auth.users)** | Login-Identitäten der Admins + Vorstände | ✓ | — (nicht enthalten) |
| **Edge Functions** | Source-Code | — | — (Git-Repo, eigene Verantwortung) |
| **Frontend (HTML/JS)** | bewerbung.html, dashboard.html, status_index.html | — | — (Git-Repo, eigene Verantwortung) |

> **Hinweis:** Das Wochen-Backup sichert die Anwendungsdaten (Tabellen + Anhänge), nicht die Auth-Identitäten der eingeloggten Mitarbeiter. Die Auth-Tabelle liegt nur im Supabase-Auto-Backup. Das ist vertretbar — die Login-Whitelist lässt sich aus `csc_dashboard_user` jederzeit neu aufbauen.

---

## 2. Automatische Backups (Supabase)

### Was Supabase macht

- **Daily Backups** mit 7 Tagen Retention (Pro-Plan)
- **PITR** (Point-in-Time-Recovery) auf 7 Tage — du kannst auf jeden Zeitpunkt der letzten 7 Tage zurückrollen
- **Read replicas** möglich (bei größeren Plänen)

### Wo zu finden

Supabase Dashboard → Projekt **Mariana** (gvzayggvtlychyjbnsgv) → **Database** → **Backups**

### Was du beachten musst

- **7-Tage-Fenster** — wenn ein Problem länger unentdeckt bleibt, sind alte Backups weg. Genau diese Lücke schließt das Wochen-Backup (Abschnitt 3): es behält standardmäßig 12 Stände, also ca. 3 Monate.
- **Storage-Bucket** wird mit gesichert — aber Restore ist umständlich (über Support-Ticket)
- Backup ist **nicht automatisch downloadbar** — du brauchst dafür entweder Supabase-Restore oder das Wochen-Backup

---

## 3. Wöchentliches Off-Site-Backup (Windows, automatisiert)

Das ist die **eingerichtete Standard-Routine**. Ein einziges Python-Skript erledigt alles, ohne Server, ohne Linux, ohne pg_dump.

| Datei | Aufgabe |
|---|---|
| `backup.py` | Liest alle `csc_`-Tabellen über die Supabase-REST-API als JSON, lädt alle Dateien aus dem Storage-Bucket, packt beides plus eine `BACKUP-INFO.txt` in eine **AES-verschlüsselte ZIP**. Rotiert alte Backups. |
| `backup_config.txt` | Zugangsdaten (Service-Role-Key, Backup-Passwort, Ziel-Ordner, Anzahl der zu behaltenden Backups). Liegt **neben** `backup.py`. |
| `ANLEITUNG_BACKUP_WINDOWS.md` | Schritt-für-Schritt-Einrichtung. |

**Wichtig:** Ein reines Datenbank-Backup enthält nur die Datei-*Pfade* der Anhänge, nicht die hochgeladenen Dateien selbst. `backup.py` sichert deshalb den Bucket `bewerbung-anhaenge` mit. Erst Tabellen plus Anhänge zusammen sind ein vollständiges Backup — beides steckt in derselben ZIP.

### Voraussetzungen

- Windows-PC mit installiertem **Python 3** (Häkchen „Add python.exe to PATH" bei der Installation)
- Das Python-Modul **`pyzipper`** (`pip install pyzipper`) für die AES-Verschlüsselung

### Einrichtung (einmalig)

Die vollständige, bebilderte Anleitung steht in **`ANLEITUNG_BACKUP_WINDOWS.md`** (9 Schritte). Kurzfassung:

1. Python installieren, `pip install pyzipper` ausführen.
2. `backup.py` + `backup_config.txt` in einen gemeinsamen Ordner legen, z. B. `C:\Users\<Name>\Dokumente\CSC-Backup-Tool`.
3. In `backup_config.txt` eintragen:
   - `SERVICE_KEY` — der **service_role**-Key aus Supabase → Project Settings → API Keys (nicht der `anon`-Key)
   - `BACKUP_PASSWORT` — frei wählbares, starkes Passwort; verschlüsselt die ZIP. **Ohne dieses Passwort ist kein Restore möglich** — in den Passwort-Manager schreiben.
   - `ZIEL_ORDNER` — am besten ein OneDrive-Ordner, dann liegt das Backup automatisch auch außerhalb des PCs
   - `ANZAHL_BEHALTEN` — wie viele Stände aufgehoben werden (Standard 12 ≈ 3 Monate)
4. Doppelklick auf `backup.py` als ersten Test → es entsteht eine `CSC-Backup_JAHR-MONAT-TAG_UHRZEIT.zip`.
5. ZIP testweise mit dem Backup-Passwort öffnen (Schritt 7 der Anleitung) — sie muss `datenbank/`, `anhaenge/` und `BACKUP-INFO.txt` enthalten.
6. In der **Windows-Aufgabenplanung** eine wöchentliche Aufgabe „CSC Backup" anlegen:
   - Programm/Skript: `python`
   - Argumente: `"C:\Users\<Name>\Dokumente\CSC-Backup-Tool\backup.py" --auto`
   - Starten in: der Ordner ohne Anführungszeichen
   - „Unabhängig von der Benutzeranmeldung ausführen" + „verpassten Start nachholen" aktivieren

Der Schalter `--auto` sorgt dafür, dass das Skript bei automatischen Läufen ohne Nachfrage durchläuft und sich von selbst schließt.

### Manueller Aufruf / Test

Doppelklick auf `backup.py`. Das Fenster bleibt offen und zeigt jeden Schritt; am Ende steht der Pfad der erzeugten ZIP. Bricht etwas ab, nennt die Fehlermeldung in der Regel direkt die Ursache (fehlender Key, Tippfehler in der Config, `pyzipper` nicht installiert).

---

## 4. Manuelle Exports (zusätzlich)

Als Backup-Ergänzung — speziell vor größeren Migrationen / Releases.

### Methode A: SQL-Export aller csc-Tabellen

Im Supabase-SQL-Editor:

```sql
-- Bewerbungen als JSONB-Array exportieren
COPY (
  SELECT jsonb_agg(b) FROM csc_bewerbungen b
) TO STDOUT;

-- Oder pro Tabelle als CSV
\copy csc_bewerbungen TO '~/backup_bewerbungen_2026-05-17.csv' CSV HEADER;
\copy csc_bewerbung_anhaenge TO '~/backup_anhaenge_2026-05-17.csv' CSV HEADER;
\copy csc_bewerbung_notizen TO '~/backup_notizen_2026-05-17.csv' CSV HEADER;
\copy csc_vereine TO '~/backup_vereine_2026-05-17.csv' CSV HEADER;
```

### Methode B: pg_dump über Supabase-Connection-String

```bash
# Connection-String aus Supabase → Project Settings → Database → Connection string (Direct connection)
pg_dump "postgres://postgres:[PASSWORD]@db.gvzayggvtlychyjbnsgv.supabase.co:5432/postgres" \
  --table='csc_*' \
  --no-owner \
  --no-acl \
  > backup_2026-05-17.sql
```

### Methode C: Storage-Files manuell sichern

Über die Supabase-UI (Storage → Bucket `bewerbung-anhaenge` → Files herunterladen) oder via JS in der Browser-Console des Dashboards (mit hauptverein_admin eingeloggt):

```js
// Alle Files listen und Download-URLs sammeln
const { data } = await sb.storage.from('bewerbung-anhaenge').list('', { limit: 1000 });
for (const item of data) {
  const { data: signed } = await sb.storage.from('bewerbung-anhaenge')
    .createSignedUrl(item.name, 3600);
  console.log(item.name, signed?.signedUrl);
}
```

> Im Normalbetrieb sind diese drei Methoden nicht nötig — das Wochen-Backup deckt denselben Inhalt ab. Sie sind die Rückfall-Optionen, falls der Backup-PC ausfällt oder ein Ad-hoc-Snapshot vor einer Migration gebraucht wird.

---

## 5. Wer hat Zugang zu Backups?

| Rolle | Zugriff | Verantwortung |
|---|---|---|
| **Andre** (Initial-Admin) | Supabase-Owner, Service-Role-Key, Database-Connection-String, Backup-Passwort | Backup-Routine betreiben, Recovery durchführen |
| **Hauptverein-Admins** | Dashboard-Lesezugriff, kein direkter DB-Zugang | Datenschutz-Mängel melden |
| **Vorstände** | nur eigener Verein, kein Backup-Zugang | nur Operation |

⚠️ **Backup-Files NIEMALS** unverschlüsselt mailen oder ungeschützt in Cloud-Storage ablegen — sie enthalten alle Bewerber-Daten (Adressen, Telefon, ggf. IBAN, Steuer-IDs). Die ZIP aus `backup.py` ist AES-verschlüsselt; sie darf in OneDrive liegen, das **Passwort** aber nicht im selben OneDrive-Ordner.

> **Single-Point-of-Failure beachten:** Backup-Passwort und Service-Role-Key liegen aktuell nur bei Andre. Geht beides verloren, sind die ZIP-Backups wertlos. Beides gehört in einen Passwort-Manager, und für den Fall eines Personal-Wechsels sollte eine zweite vertrauenswürdige Person Notfall-Zugang haben (siehe Abschnitt 8).

---

## 6. Recovery-Pfad

### Szenario A: Eine Bewerbung versehentlich gelöscht

1. Supabase Dashboard → Database → Backups → **Point-in-Time-Recovery**
2. Zeitpunkt VOR der Löschung wählen
3. **Restore** klicken — Supabase erstellt einen Snapshot
4. Aus dem Snapshot die gelöschte Zeile per SQL kopieren, ins Live-System einfügen
5. Snapshot wieder löschen

### Szenario B: Eine Tabelle ist korrupt

1. Aktuellste Wochen-Backup-ZIP mit dem Backup-Passwort öffnen
2. Im Ordner `datenbank/` liegt die betroffene Tabelle als JSON
3. Daten daraus per SQL bzw. Supabase-Editor wieder einspielen (`TRUNCATE` der Tabelle, dann JSON-Inhalt importieren)

### Szenario C: Supabase-Projekt total weg

1. Neues Supabase-Projekt anlegen (gleiche Region: **EU**, bestätigt eu-west-1)
2. Schema-SQL aus Git-Repo neu laden (`05_SQL-und-EdgeFunctions/`)
3. Daten aus der aktuellsten Wochen-Backup-ZIP einspielen (Ordner `datenbank/`)
4. Edge-Functions neu deployen (Code aus Git)
5. Storage-Files aus dem Ordner `anhaenge/` der ZIP in den neuen Bucket hochladen
6. Frontend-Konfiguration anpassen (neue Supabase-URL + anon-Key)

**Geschätzte Dauer:** 2–4 Stunden, je nach Daten-Menge.

### Szenario D: DSGVO-Datenleck

→ siehe separates Dokument: **roter_knopf_dsgvo.md**

---

## 7. Empfohlene Routine

| Frequenz | Action |
|---|---|
| **Täglich (automatisch)** | Supabase Auto-Backup |
| **Wöchentlich (automatisch)** | `backup.py` per Windows-Aufgabenplanung — verschlüsselte ZIP von DB + Anhängen, Ablage in OneDrive |
| **Vor jedem größeren Release/Migration** | Manuelles SQL-Snapshot (Methode A) |
| **Quartalsweise** | Recovery-Drill: eine Backup-ZIP testweise öffnen (mit dem Backup-Passwort) und stichprobenartig prüfen, dass `datenbank/` und `anhaenge/` vollständig sind. Damit ist sicher, dass die Verschlüsselung wirklich wiederherstellbar ist. |
| **Monatlich (kurzer Blick)** | In der Windows-Aufgabenplanung das „Letzte Ausführungsergebnis" der Aufgabe „CSC Backup" prüfen — steht dort `0x0`, lief alles. |

> **Schwachstelle der Windows-Lösung:** Das Backup läuft nur, wenn der PC zur geplanten Zeit an ist. Die Option „verpassten Start nachholen" fängt das ab, solange der PC wenigstens irgendwann in der Woche läuft. Steht der PC länger still, fehlt ein Wochen-Stand — das Supabase-Auto-Backup deckt diese Lücke für 7 Tage ab. Der monatliche Blick auf das Ausführungsergebnis stellt sicher, dass das nicht unbemerkt bleibt.

---

## 8. Was NICHT vergessen

- **Service-Role-Key** sicher aufbewahren (Passwort-Manager) — der gibt Admin-Zugang zu allem
- **Backup-Passwort** im Passwort-Manager ablegen — ohne es ist keine einzige ZIP wiederherstellbar
- **Connection-String** mit Passwort separat aufbewahren
- Bei Personal-Wechsel (z. B. neuer Initial-Admin): Zugänge ordentlich übertragen, alte Keys rotieren
- **DSGVO-Aufbewahrungsfrist** beachten: Bewerber-Daten dürfen nicht ewig liegen. Daten abgelehnter Bewerbungen nach 6 Monaten löschen, sofern der Bewerber nicht einer längeren Speicherung zustimmt. Die Auto-Cleanup-Funktion erledigt das im Live-System — alte Backup-ZIPs werden über `ANZAHL_BEHALTEN` rotiert und nach ca. 3 Monaten überschrieben.

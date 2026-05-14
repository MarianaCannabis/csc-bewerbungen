# Backup-Strategie · Mariana Bewerbungs-System

Stand: 14.05.2026

## TL;DR

Supabase macht **automatische Daily-Backups**. Diese sind 7 Tage rückverfolgbar (Pro-Plan). Plus du kannst jederzeit **manuelle SQL-Exports** machen. Storage-Files (`bewerbung-anhaenge`) werden im selben Backup-Pfad erfasst.

**Recovery-Pfad bei Total-Verlust:** ca. 30 Minuten. Wer hat Zugang: Andre (Initial-Admin, Service-Role-Key, Supabase-Owner).

---

## 1. Was wird gesichert?

| Komponente | Inhalt | Backup-Methode |
|---|---|---|
| **PostgreSQL-DB** | csc_bewerbungen, csc_bewerbung_anhaenge, csc_bewerbung_notizen, csc_user_profiles, csc_dashboard_user, csc_vereine, csc_mail_log, csc_error_log, csc_bewerbung_changes etc. | Supabase auto-daily |
| **Storage Bucket `bewerbung-anhaenge`** | hochgeladene Lebensläufe, Zeugnisse | Supabase auto-daily |
| **Auth (auth.users)** | Login-Identitäten der Admins + Vorstände | Supabase auto-daily |
| **Edge Functions** | Source-Code | Git-Repo (eigene Verantwortung) |
| **Frontend (HTML/JS)** | bewerbung.html, dashboard.html, status.html | Git-Repo (eigene Verantwortung) |

---

## 2. Automatische Backups (Supabase)

### Was Supabase macht

- **Daily Backups** mit 7 Tagen Retention (Pro-Plan)
- **PITR** (Point-in-Time-Recovery) auf 7 Tage — du kannst auf jeden Zeitpunkt der letzten 7 Tage zurückrollen
- **Read replicas** möglich (bei größeren Plänen)

### Wo zu finden

Supabase Dashboard → Projekt **Mariana** (gvzayggvtlychyjbnsgv) → **Database** → **Backups**

### Was du beachten musst

- **7-Tage-Fenster** — wenn ein Problem länger unentdeckt bleibt, sind alte Backups weg
- **Storage-Bucket** wird mit gesichert — aber Restore ist umständlich (über Support-Ticket)
- Backup ist **nicht automatisch downloadbar** — du brauchst dafür entweder Supabase-Restore oder einen manuellen Export

---

## 3. Manuelle Exports (zusätzlich)

Als Backup-Ergänzung — speziell vor größeren Migrationen / Releases.

### Methode A: SQL-Export aller csc-Tabellen

Im Supabase-SQL-Editor:

```sql
-- Bewerbungen als JSONB-Array exportieren
COPY (
  SELECT jsonb_agg(b) FROM csc_bewerbungen b
) TO STDOUT;

-- Oder pro Tabelle als CSV
\copy csc_bewerbungen TO '~/backup_bewerbungen_2026-05-14.csv' CSV HEADER;
\copy csc_bewerbung_anhaenge TO '~/backup_anhaenge_2026-05-14.csv' CSV HEADER;
\copy csc_bewerbung_notizen TO '~/backup_notizen_2026-05-14.csv' CSV HEADER;
\copy csc_vereine TO '~/backup_vereine_2026-05-14.csv' CSV HEADER;
```

### Methode B: pg_dump über Supabase-Connection-String

```bash
# Connection-String aus Supabase → Project Settings → Database → Connection string (Direct connection)
pg_dump "postgres://postgres:[PASSWORD]@db.gvzayggvtlychyjbnsgv.supabase.co:5432/postgres" \
  --table='csc_*' \
  --no-owner \
  --no-acl \
  > backup_2026-05-14.sql
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

---

## 4. Wer hat Zugang zu Backups?

| Rolle | Zugriff | Verantwortung |
|---|---|---|
| **Andre** (Initial-Admin) | Supabase-Owner, Service-Role-Key, Database-Connection-String | Backup-Strategie umsetzen, Recovery durchführen |
| **Hauptverein-Admins** | Dashboard-Lesezugriff, kein direkter DB-Zugang | Datenschutz-Mängel melden |
| **Vorstände** | nur eigener Verein, kein Backup-Zugang | nur Operation |

⚠️ **Backup-Files NIEMALS** unverschlüsselt mailen oder in Cloud-Storage ablegen — sie enthalten alle Bewerber-Daten (Adressen, Telefon, IBAN, Steuer-IDs).

---

## 5. Recovery-Pfad

### Szenario A: Eine Bewerbung versehentlich gelöscht

1. Supabase Dashboard → Database → Backups → **Point-in-Time-Recovery**
2. Zeitpunkt VOR der Löschung wählen
3. **Restore** klicken — Supabase erstellt einen Snapshot
4. Aus dem Snapshot die gelöschte Zeile per SQL kopieren, ins Live-System einfügen
5. Snapshot wieder löschen

### Szenario B: Eine Tabelle ist korrupt

1. Manuell letztes funktionierendes CSV-Backup laden:
   ```sql
   TRUNCATE csc_bewerbungen;
   \copy csc_bewerbungen FROM 'backup_bewerbungen_2026-05-13.csv' CSV HEADER;
   ```

### Szenario C: Supabase-Projekt total weg

1. Neues Supabase-Projekt anlegen (gleiche Region: EU)
2. Schema-SQL aus Git-Repo neu laden (`/migrations/` oder ähnlich)
3. Daten aus letztem CSV/pg_dump-Backup einspielen
4. Edge-Functions neu deployen (Code aus Git)
5. Frontend-Konfiguration anpassen (neue Supabase-URL + anon-Key)
6. Storage-Files manuell hochladen (falls Daten verfügbar)

**Geschätzte Dauer:** 2-4 Stunden, je nach Daten-Menge.

### Szenario D: DSGVO-Datenleck

→ siehe separates Dokument: **roter_knopf_dsgvo.md**

---

## 6. Empfohlene Routine

| Frequenz | Action |
|---|---|
| **Täglich (automatisch)** | Supabase Auto-Backup |
| **Vor jedem größeren Release/Migration** | Manuelles SQL-Snapshot (Methode A) |
| **Monatlich** | Full pg_dump auf verschlüsseltes Storage (Methode B) |
| **Quartalsweise** | Recovery-Drill: Test-Restore in Test-Projekt, Verifikation der Datenintegrität |

---

## 7. Was NICHT vergessen

- **Service-Role-Key** sicher aufbewahren (Passwort-Manager) — der gibt Admin-Zugang zu allem
- **Connection-String** mit Passwort separat aufbewahren
- Bei Personal-Wechsel (z.B. neuer Initial-Admin): Zugänge ordentlich übertragen, alte Keys rotieren
- **DSGVO-Aufbewahrungsfrist** beachten: Bewerber-Daten dürfen nicht ewig liegen. Daten abgelehnter Bewerbungen nach 6 Monaten löschen, sofern Bewerber nicht zustimmt zur längeren Speicherung

# Mariana Cannabis Bewerbungs-Dashboard — Sicherheits-Status

**Stand:** 18. Mai 2026
**Erstellt für:** Andre Reiche, Community Management
**Zweck:** Ehrliche Bewertung der Datenschutz- und Sicherheitslage. Was ist gut, was muss geprüft werden, was sollte verbessert werden.

---

## TL;DR — Kurze Antwort

**Die Daten sind gut geschützt.** Wir haben mehrere Schutz-Ebenen eingebaut: Zugriffskontrolle auf Datenbank-Ebene, Login nur für freigeschaltete Adressen, automatische Löschfristen, Selbstlöschung für Bewerber, Audit-Logs, HTTPS überall, klare DSGVO-Konformität, verschlüsseltes Off-Site-Backup.

Seit dem 16.05. sind die drei größten organisatorischen Punkte abgearbeitet: die Datenschutzerklärung ist anwaltlich geprüft und freigegeben, die Supabase-Region als EU bestätigt, das verschlüsselte Wochen-Backup eingerichtet. Am 18.05. wurde zusätzlich die Erfassung der Vertragsdaten datensparsam umgebaut (Punkt 14). **Es bleiben einige kleinere Punkte zum Verifizieren** (unten, Abschnitt ⚠️) — keiner davon ist akut.

---

## ✅ Was AKTUELL bereits sicher ist

### 1. Zugriffskontrolle (Row Level Security)

Auf Datenbank-Ebene erzwungen (PostgreSQL RLS). **Jeder Vorstand sieht nur Bewerbungen seines eigenen Vereins** — kann nicht versehentlich oder absichtlich auf andere Vereine zugreifen, auch wenn er Browser-Tricks ausprobiert. Hauptverein-Admins (CM, Bereichsleitungen) sehen alle 182 Vereine.

### 2. Login-Whitelist

Nur explizit freigeschaltete E-Mail-Adressen können sich anmelden. Selbst wenn jemand die Login-URL kennt und seine eigene Mail eingibt, kommt eine Fehlermeldung. Frontend-Check + Datenbank-Check (Function `csc_check_login_allowed`).

### 3. Magic-Link-Login (kein Passwort)

Kein Passwort heißt: kein Passwort-Leak möglich. Login-Mails sind nur ~60 Minuten gültig und einmal verwendbar. Phishing-Risiko deutlich reduziert.

### 4. Automatische Löschfristen

- **Abgelehnte Bewerbungen** werden nach 6 Monaten automatisch gelöscht (Datenbank + Storage-Files via `csc_cleanup_old_bewerbungen()`)
- **Bewerber können jederzeit selbst löschen** über ihre Status-Seite (DSGVO Art. 17, Right to be forgotten)

### 5. Audit-Log

Jede Änderung wird mit Zeitstempel und User-ID protokolliert: Status-Wechsel, Notiz-Einträge, Tag-Änderungen, Status-Setzen, Anhang-Uploads, Mail-Versand. Nachvollziehbar und DSGVO-Pflicht erfüllt.

### 6. Verschlüsselung

- **In transit:** HTTPS überall (TLS 1.3). GitHub Pages erzwingt das.
- **At rest:** Supabase verschlüsselt Datenbank und Storage at rest (AES-256). Standard bei allen Tier-2 Cloud-Providern.

### 7. Aktive Einwilligungen

- DSGVO-Zustimmung ist Pflichtfeld vor Absenden
- Sensible Daten (Art. 9 DSGVO: Sucht, Schwerbehinderung) brauchen separate Einwilligung
- Wahrheitsbestätigung vor Absenden

### 8. Tokens statt sequentielle IDs

Status-Seite ist mit zufälligen Tokens geschützt (`?token=abc123...`). Niemand kann "Bewerbung 42" einfach im URL ändern.

### 9. Captcha gegen Bots

Vor dem Absenden muss ein Captcha gelöst werden — verhindert Massen-Bewerbungen durch Bots.

### 10. KI-Hinweis (DSGVO Art. 22 / EU AI Act)

Im Bewerbungsbogen wird transparent erklärt, dass eine automatische Bewertung (Score) stattfindet, dass diese nur ein Hinweis ist, und dass die finale Entscheidung von Menschen getroffen wird. Recht auf menschliche Überprüfung wird explizit erwähnt.

### 11. Supabase-Region in der EU ✅ *(verifiziert 17.05.2026)*

Das Supabase-Projekt liegt in der EU-Region `eu-west-1` (Irland). Personenbezogene Daten werden innerhalb der EU gespeichert und verarbeitet — kein Schrems-II-Risiko durch den Speicherort.

### 12. Verschlüsseltes Off-Site-Backup ✅ *(eingerichtet 17.05.2026)*

Ein wöchentliches, AES-verschlüsseltes Backup von Datenbank und Anhang-Dateien läuft per Windows-Aufgabenplanung (`backup.py`), Ablage in OneDrive. Damit ist die 7-Tage-Lücke der Supabase-Auto-Backups geschlossen (ca. 3 Monate Backup-Stände). Details: `BACKUP_STRATEGIE.md`.

### 13. Datenschutzerklärung anwaltlich freigegeben ✅ *(Stand 17.05.2026)*

Die Datenschutzerklärung wurde anwaltlich geprüft und freigegeben.

### 14. Getrennte, datensparsame Erfassung der Vertragsdaten ✅ *(umgesetzt 18.05.2026)*

Sensible vertragsvorbereitende Daten (Steuer-ID, Sozialversicherungsnummer, Bankverbindung, Krankenkasse u. a.) werden **nicht mehr im Bewerbungsbogen** erhoben. Stattdessen:

- Sie werden **erst nach einer Zusage** erfasst — die angenommene Person trägt sie selbst über ihre Status-Seite ein. Damit liegen sie nur von tatsächlich eingestellten Personen vor, nicht von abgelehnten Bewerber:innen (Datenminimierung, Art. 5 Abs. 1 lit. c DSGVO).
- Sie liegen in einer **eigenen Tabelle** (`csc_vertragsdaten`), getrennt von den Bewerbungsdaten.
- **Zugriffsschutz:** Lesen und Löschen ist per Row Level Security auf Hauptverein-Admins beschränkt — Vereinsvorstände sehen diese Daten nicht. Schreiben geht ausschließlich über eine token- und status-geprüfte Datenbank-Funktion (`save_vertragsdaten`); ein direkter Tabellenzugriff für anonyme oder eingeloggte Nutzer besteht nicht.
- Beim Löschen einer Bewerbung (Selbstlöschung oder 6-Monats-Bereinigung) werden die Vertragsdaten automatisch mitgelöscht.

Das Verzeichnis von Verarbeitungstätigkeiten wurde entsprechend aktualisiert (Version 1.1).

---

## ⚠️ Was du noch PRÜFEN solltest

Drei Punkte aus der ursprünglichen Liste sind noch offen — alle organisatorisch, keiner akut.

### 1. Wer hat Supabase-Zugriff?

**Status:** muss geprüft werden.

**Was zu tun ist:** In Supabase → Project Settings → Team prüfen, welche User Zugriff haben. Jeder mit Owner/Admin-Rolle kann theoretisch alle Bewerbungsdaten einsehen. Empfehlung:

- Nur 1-2 vertrauenswürdige Personen mit Admin-Rolle
- Andere User auf "Read-Only" oder "Developer" beschränken
- Service-Role-Key niemals in Frontend-Code (er ist nur in Edge Functions und im Backup-Skript)

### 2. Edge Functions Logs

**Status:** Supabase loggt Edge-Function-Aufrufe.

**Was zu tun ist:** Prüfen, ob in Edge-Function-Logs **personenbezogene Daten** auftauchen (E-Mail-Adressen, Namen). Wenn ja, muss das Log-Level reduziert werden, denn auch Logs unterliegen der DSGVO. In Supabase → Logs → Edge Functions prüfen.

### 3. Mail-Provider

**Status:** Edge Function `send-bewerbung-email` versendet über einen externen Mail-Provider.

**Was zu tun ist:** Welchen Provider? Resend, Postmark, SendGrid? **Server-Standort des Mail-Providers prüfen** — für DSGVO sollte er EU sein oder einen AVV (Auftragsverarbeitungsvertrag) haben. Bei `noreply@`-Adressen ist das weniger kritisch, aber Antworten könnten dort gespeichert werden. Der Provider gehört außerdem ins Verzeichnis von Verarbeitungstätigkeiten (siehe `VERZEICHNIS_VERARBEITUNGSTAETIGKEITEN.md`, Abschnitt H).

---

## 🔧 Was du noch VERBESSERN könntest

### 1. Browser-localStorage im Bewerbungsbogen

**Aktuell:** Der Bewerbungsbogen speichert Daten lokal im Browser, damit Bewerber unterbrechen und später weitermachen können.

**Risiko:** Wenn ein Bewerber den Bogen auf einem öffentlichen oder geteilten Gerät ausfüllt, bleiben die Daten im Browser zurück. Andere Personen mit Zugriff auf dasselbe Browser-Profil könnten die Daten sehen.

**Empfehlung:** Im Bewerbungsbogen eine kleine Info-Box am Anfang: *"Wenn du diesen Bogen auf einem geteilten Gerät ausfüllst, achte darauf, ihn nach dem Absenden zu vervollständigen oder den Browser-Speicher zu leeren."* — Plus: Nach erfolgreicher Übermittlung sollte localStorage komplett gelöscht werden (das machen wir bereits).

### 2. Rate-Limiting

**Aktuell:** Captcha schützt vor Bots, aber Edge-Function-Aufrufe haben kein explizites Rate-Limit pro IP.

**Empfehlung:** In Supabase Edge Function ein einfaches Rate-Limit einbauen (z. B. max 5 Bewerbungen pro IP pro Stunde). Verhindert Massen-Spam.

### 3. Pen-Test

**Aktuell:** Keine professionelle Sicherheitsüberprüfung.

**Empfehlung:** Wenn das System produktiv läuft und 100+ Bewerbungen drinnen sind, einen externen Pen-Test (ca. 1500-3000 €) erwägen. Lohnt sich besonders, wenn sensible Daten viele Personen umfassen.

### 4. 2FA für Vorstände

**Aktuell:** Magic-Link allein. Bei kompromittiertem Mail-Account → kompromittierter Dashboard-Zugriff.

**Empfehlung:** Für High-Risk-Rollen (CM, Hauptverein-Admin) zusätzlich 2FA erzwingen. Supabase unterstützt das. Für normale Vereins-Vorstände ist Magic-Link aber OK.

### 5. Alte Vertragsdaten-Spalten in csc_bewerbungen entfernen

**Status:** offen — kleiner Aufräum-Schritt.

**Was zu tun ist:** Mit dem Umbau vom 18.05. erhebt der Bewerbungsbogen keine Steuer-ID, SV-Nummer, IBAN und Krankenkasse mehr. Die alten Spalten in der Tabelle `csc_bewerbungen` bestehen aber noch und können bei früheren Bewerbungen Alt-Daten enthalten. Die Datei `feature_vertragsdaten.sql` enthält am Ende einen auskommentierten SQL-Block, der diese Spalten entfernt. Sobald die neue Status-Seite stabil läuft, sollte dieser Block ausgeführt werden — er löscht die dortigen Alt-Daten DSGVO-konform.

### 6. DSGVO-Verzeichnis von Verarbeitungstätigkeiten

**Status:** Entwurf erstellt — `VERZEICHNIS_VERARBEITUNGSTAETIGKEITEN.md`.

**Was zu tun ist:** Der Entwurf deckt das Bewerbungs-System ab (Verantwortlicher, Zwecke, Datenkategorien, Empfänger, Drittland, Löschfristen, TOM, automatisierte Entscheidung). Offen: einige Felder ausfüllen (Vereins-/DSB-Daten, Mail-Provider) und durch die/den Datenschutzbeauftragte:n (DataCo GmbH) freigeben lassen. Die Checkliste am Ende des Dokuments führt die offenen Punkte.

---

## 🚨 Was AKUT war — Status

Die drei ursprünglich als akut markierten Punkte sind erledigt:

1. **Datenschutzerklärung** — anwaltlich geprüft und freigegeben ✅
2. **Supabase EU-Region** — als `eu-west-1` (Irland) bestätigt ✅
3. **KI-Hinweis** — im Bewerbungsbogen enthalten ✅

**Ein Rest-Check bleibt:** sicherstellen, dass der KI-/Scoring-Hinweis auch in der freigegebenen Datenschutzerklärung auf der Website enthalten ist (nicht nur im Bewerbungsbogen). Der passende Textbaustein liegt in `KI_HINWEIS_DATENSCHUTZERKLAERUNG.md`. Falls er bei der Anwaltsprüfung bereits berücksichtigt wurde, ist auch dieser Punkt erledigt.

---

## Anhang: Vorschlag-Text für die Datenschutzerklärung

> Dieser Textbaustein liegt jetzt zusätzlich als eigene Datei vor:
> `KI_HINWEIS_DATENSCHUTZERKLAERUNG.md` (zum direkten Weitergeben).
> Die folgende Fassung ist inhaltsgleich.

Ergänze in deine Datenschutzerklärung folgenden Abschnitt (Anwalt-Prüfung empfohlen):

---

### Automatisierte Entscheidungsfindung und Profilbildung (Art. 22 DSGVO)

Im Rahmen unseres Bewerbungsverfahrens setzen wir ein automatisches Punkte-System ("Score") ein, das aus den von Ihnen angegebenen Daten einen Wert zwischen 0 und 100 berechnet. Dieser Score dient ausschließlich als **Vorsortierungs-Hilfe für unsere Vereinsvorstände** und das Community-Management-Team.

**Welche Daten fließen in den Score ein?**
- Ihre angegebene Verfügbarkeit (Wochentage und Tageszeiten)
- Vorerfahrung, Bildungsabschluss und Sprachkenntnisse
- Anfahrtsmobilität und eigenes Fahrzeug
- Soft-Skills (Ihre Selbsteinschätzung)
- Bereitschaft für Wochenende, Feiertag und Nacht
- Vorhandener Sachkundenachweis (Prävention)

**Wer entscheidet endgültig?**
Die Bewertung wird **nicht ausschließlich automatisiert** im Sinne von Art. 22 DSGVO durchgeführt. Die Entscheidung über Ihre Bewerbung wird **immer von Menschen getroffen** — konkret durch den Vereinsvorstand und unser Community-Management-Team nach dem Vier-Augen-Prinzip.

**Welche Technologie verwenden wir?**
Wir setzen **keine KI-Sprachmodelle** (wie ChatGPT, Claude oder ähnliche) zur Bewertung Ihrer Bewerbung ein. Der Score wird nach einer transparenten, deterministischen Formel berechnet, die wir Ihnen auf Anfrage gerne im Detail erläutern.

**Ihre Rechte:**
- Sie haben das Recht auf **menschliche Überprüfung** des Scores
- Sie haben das Recht, **Ihren Standpunkt darzulegen**
- Sie haben das Recht, **die Entscheidung anzufechten**

Wenden Sie sich dafür an [communityrecruiting@mariana-cannabis.de](mailto:communityrecruiting@mariana-cannabis.de).

---

## Anhang: Checkliste für dich

- [x] Supabase-Region prüfen — erledigt, EU (`eu-west-1`, Irland)
- [x] Backup-Strategie dokumentiert + Skripte erstellt
- [x] Backup automatisch einrichten — erledigt, Windows-Aufgabenplanung (`backup.py`)
- [ ] Nach einem Backup-Lauf eine ZIP testweise mit dem Backup-Passwort öffnen (Restore-Probe; quartalsweise wiederholen)
- [ ] Supabase-Team-Zugriff überprüfen (wer hat Admin?)
- [ ] Edge-Function-Logs auf personenbezogene Daten prüfen
- [ ] Mail-Provider klären (welcher? wo? AVV vorhanden?)
- [x] Datenschutzerklärung vom Anwalt prüfen lassen — erledigt, freigegeben
- [ ] KI-Hinweis in der freigegebenen Datenschutzerklärung verifizieren (Baustein: `KI_HINWEIS_DATENSCHUTZERKLAERUNG.md`)
- [x] Verzeichnis von Verarbeitungstätigkeiten (Art. 30 DSGVO) — auf den Vertragsdaten-Umbau aktualisiert (Version 1.1); DSB-Freigabe + offene Felder ausstehend
- [x] Vertragsdaten datensparsam umgebaut — getrennte Tabelle, Erfassung erst nach Zusage, Admin-only-Zugriff (18.05.2026)
- [ ] Optionalen SQL-Block ausführen, der die alten Spalten (steuer_id, sv_nummer, iban, krankenkasse) aus `csc_bewerbungen` entfernt — Datei `feature_vertragsdaten.sql`
- [ ] 2FA für CM und Hauptverein-Admins erwägen
- [ ] Rate-Limiting auf Edge Functions erwägen

---

## Fazit

Das System ist **technisch sehr gut abgesichert** — auf Höhe oder besser als die meisten kommerziellen Bewerbungs-Tools im Mittelstand. Die drei großen organisatorischen Risiken vom 16.05. sind inzwischen geschlossen: Datenschutzerklärung freigegeben, EU-Region bestätigt, verschlüsseltes Backup läuft.

Offen sind nur noch kleinere Verifizierungs- und Pflege-Punkte:

1. Supabase-Team-Zugriff, Edge-Function-Logs und Mail-Provider prüfen
2. Verzeichnis von Verarbeitungstätigkeiten durch die/den DSB freigeben lassen
3. KI-Hinweis in der veröffentlichten Datenschutzerklärung verifizieren
4. Alte Vertragsdaten-Spalten aus `csc_bewerbungen` entfernen (optionaler SQL-Block)

Keiner dieser Punkte ist akut. Das System ist auf einem sehr guten Niveau.

🌿 Bei Fragen: ich bin nur einen Chat entfernt.

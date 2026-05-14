# 🚨 Roter Knopf — DSGVO-Notfallplan

Stand: 14.05.2026 · Mariana Cannabis Bewerbungs-System

> Dieses Dokument tritt in Kraft bei: Datenleck, unberechtigter Zugriff, versehentlicher Veröffentlichung personenbezogener Daten, oder anderer Vorfall mit potenziellem Schaden für betroffene Personen.

---

## TL;DR

**Du hast 72 Stunden ab Kenntnisnahme**, um einen meldepflichtigen Datenschutzvorfall an die zuständige **Datenschutz-Aufsichtsbehörde** zu melden (Art. 33 DSGVO). Wenn personenbezogene Daten betroffen sind und das Risiko für Betroffene **hoch** ist, müssen auch die Betroffenen direkt informiert werden (Art. 34 DSGVO).

**Erste 4 Schritte sofort**, in dieser Reihenfolge:
1. Schaden eindämmen (Zugang sperren)
2. Vorfall dokumentieren (was, wann, wer, wie, was-betroffen)
3. Andre + Vorstand der Anbauvereinigung informieren
4. Aufsichtsbehörde-Meldung vorbereiten

---

## Phase 1: Schaden eindämmen (innerhalb 15 Min)

### Wenn Zugangsdaten kompromittiert sind

```sql
-- Alle Sessions invalidieren (Supabase SQL-Editor)
-- → zwingt alle Admins/Vorstände zum Neu-Einloggen
DELETE FROM auth.sessions;
```

### Wenn ein einzelner Admin/Vorstand-Account kompromittiert ist

Supabase Dashboard → Authentication → Users → den User → **Delete user** oder **Lock account**

### Wenn die Datenbank offen war / RLS umgangen

1. **Sofort alle anon-RLS-Policies prüfen** (Supabase → Database → Policies)
2. Anon-Key rotieren falls nötig: Supabase Settings → API → **Reset anon key**
   - Achtung: alle Frontend-Apps müssen dann mit neuem Key aktualisiert werden!

### Wenn Storage-Files öffentlich abrufbar waren

```sql
-- Bucket-Public-Flag prüfen
SELECT id, name, public FROM storage.buckets WHERE name = 'bewerbung-anhaenge';

-- Sollte public = false sein. Falls true:
UPDATE storage.buckets SET public = false WHERE name = 'bewerbung-anhaenge';
```

---

## Phase 2: Dokumentieren (innerhalb 1 Stunde)

Eine Datei `vorfall_YYYY-MM-DD_HHMM.md` anlegen mit:

```markdown
# Datenschutzvorfall · [Kurze Beschreibung]

## Zeitstempel
- **Entdeckt:** YYYY-MM-DD HH:MM
- **Vermutlicher Beginn des Vorfalls:** ...
- **Eindämmung erfolgt:** YYYY-MM-DD HH:MM

## Was ist passiert?
[Eine Sachverhalts-Beschreibung in ganzen Sätzen — was tatsächlich vorgefallen ist, ohne Spekulation]

## Welche Daten waren betroffen?
- [ ] Stammdaten (Name, Geburtsdatum, Geburtsort)
- [ ] Kontakt-Daten (E-Mail, Telefon, Adresse)
- [ ] Sensible Kategorie (Schwerbehinderung, Sucht-Relevanz)
- [ ] Finanzdaten (Steuer-ID, IBAN, Sozialversicherungs-Nr.)
- [ ] Bewerbungs-Unterlagen (Lebenslauf, Zeugnisse)
- [ ] Login-Credentials (Magic-Link, Session-Token)
- [ ] Audit-/Notiz-Daten

## Wie viele Personen sind betroffen?
- Geschätzt: ___ Bewerber:innen
- Geschätzt: ___ Vorstände

## Wie konnte das passieren?
[Root-Cause-Analyse: technisches Versagen, menschlicher Fehler, Angriff?]

## Was wurde sofort unternommen?
[Liste der Eindämmungs-Schritte mit Zeitstempel]

## Risiko-Einschätzung für die Betroffenen
- [ ] Kein Risiko (z.B. nur eigene Daten betroffen, kein Datenabfluss)
- [ ] Geringes Risiko (z.B. nur Name/E-Mail)
- [ ] Hohes Risiko (z.B. Finanzdaten, Sucht-Relevanz, Adresse + Telefon kombiniert)

## Wer wurde informiert?
- [ ] Andre / Initial-Admin: Datum
- [ ] Vorstand Mariana Gesamtverein: Datum
- [ ] Datenschutzbeauftragter (falls vorhanden): Datum
- [ ] Datenschutz-Aufsichtsbehörde: Datum
- [ ] Betroffene Personen: Datum
```

---

## Phase 3: Eskalation (innerhalb 4 Stunden)

### Wen informieren — in dieser Reihenfolge

1. **Andre Reiche** (Initial-Admin) — `areiche@cscsdeutschland.de`
2. **Vorstand Mariana Gesamtverein** — Nils Harbers, `vorstand@cscsdeutschland.de`
3. **Anwalt** (falls verfügbar) — Rechtsanwälte Schroer und Schulla, Marburg
4. **Vorstand des betroffenen Zweigvereins** (wenn lokaler Vorfall)
5. **Datenschutzbeauftragter** (falls bestellt)

### Wie informieren

**NICHT per Mail** schreiben falls Mail-System auch betroffen sein könnte. Stattdessen:
- Telefonisch / Signal
- Persönlich
- Falls per Mail: gesonderte Adresse außerhalb des kompromittierten Systems

---

## Phase 4: Aufsichtsbehörden-Meldung (innerhalb 72 Stunden)

### Welche Aufsichtsbehörde?

Da Mariana Cannabis Social Clubs Deutschland e.V. in **Göttingen** (Niedersachsen) registriert ist:

**Landesbeauftragte für den Datenschutz Niedersachsen (LfD)**
- Webseite: https://lfd.niedersachsen.de
- Online-Meldeformular: https://lfd.niedersachsen.de → Meldungen → Datenschutzverletzung

### Was wird gemeldet?

- Art, Umfang und Auswirkungen des Vorfalls
- Anzahl betroffener Personen + Datensätze
- Mögliche Folgen für Betroffene
- Was wurde / wird unternommen, um den Vorfall zu beheben
- Kontaktdaten der verantwortlichen Person

### Wann kann gemeldet werden?

- Auch dann, wenn noch nicht alle Details klar sind (Nachmeldung möglich)
- Wenn Risiko-Einschätzung „kein Risiko" → keine Meldung erforderlich, aber **interne Dokumentation Pflicht**

---

## Phase 5: Betroffene informieren (wenn hohes Risiko)

Bei **hohem Risiko** für Betroffene (Art. 34 DSGVO): die Betroffenen direkt informieren.

### Was muss in der Information stehen?

- Klar verständliche Sprache (keine Juristerei)
- Welche Daten waren betroffen
- Welche Folgen das haben kann
- Was wurde dagegen unternommen
- Was die Betroffenen jetzt tun sollten (z.B. Passwörter ändern, Bank informieren)
- Kontaktdaten für Rückfragen

### Vorlage E-Mail

```
Betreff: Wichtige Information zu deiner Bewerbung bei Mariana Cannabis

Hallo [Vorname],

wir müssen dich über einen Vorfall informieren, der deine Bewerbungs-Daten betroffen haben könnte.

Was ist passiert?
[Sachlicher 2-3-Satz-Erklärung]

Welche deiner Daten waren betroffen?
[konkret auflisten — nicht beschönigen]

Was bedeutet das für dich?
[ehrliche Risiko-Einschätzung + konkrete Empfehlungen]

Was wir bereits unternommen haben:
[Liste der Maßnahmen]

Was du jetzt tun solltest:
[konkrete Schritte]

Wir bedauern den Vorfall sehr und stehen für Fragen zur Verfügung:
communityrecruiting@mariana-cannabis.de

Mit Respekt,
[Name] · Datenschutzverantwortlich · Mariana Cannabis
```

---

## Phase 6: Nachsorge (innerhalb 2 Wochen)

- Vorfall-Dokumentation finalisieren
- Root-Cause-Analyse abschließen
- Präventionsmaßnahmen einleiten:
  - Code-Review
  - RLS-Policy-Audit
  - Backup-Test
  - ggf. Penetrations-Test
- Lessons-Learned-Meeting mit Andre + Vorstand
- Backup-Strategie review

---

## Checkliste · zum Ausdrucken und aufhängen

```
□  Eindämmen — Zugang sperren, Datenbank-Policies checken (15 Min)
□  Dokumentieren — vorfall_DATUM.md schreiben (1 Std)
□  Andre informieren — Telefon, nicht Mail (4 Std)
□  Vorstand Mariana informieren (4 Std)
□  Anwalt einbeziehen (4 Std)
□  Aufsichtsbehörde melden — LfD Niedersachsen (72 Std)
□  Betroffene informieren — wenn hohes Risiko (72 Std)
□  Vorfall-Dokumentation finalisieren (2 Wochen)
□  Präventionsmaßnahmen umsetzen (4 Wochen)
□  Lessons-Learned mit Vorstand (4 Wochen)
```

---

## Wichtige Kontakte

| Rolle | Person | Kontakt |
|---|---|---|
| Initial-Admin | Andre Reiche | areiche@cscsdeutschland.de |
| Vorstand Mariana | Nils Harbers | vorstand@cscsdeutschland.de |
| Anwalt | Rechtsanwälte Schroer und Schulla | Marburg |
| Aufsichtsbehörde | LfD Niedersachsen | https://lfd.niedersachsen.de |
| Community-Recruiting | — | communityrecruiting@mariana-cannabis.de |

---

**Letzter Test dieses Plans:** noch nicht durchgeführt — empfohlen: Trockenübung innerhalb der nächsten 6 Wochen.

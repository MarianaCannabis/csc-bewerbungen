# Score-Removal — Offene Punkte

Score wurde am 2026-05-28 aus DSGVO-Gruenden (Art. 22 — keine automatisierten
Entscheidungen) entfernt. Dieser Commit (`score-removal-2026-05-28`) deckt:

- DB-Trigger DISABLED (`csc_compute_score_on_insert` + `_on_update`)
- Dashboard-UI: Score-Anzeige, Sort-Optionen, Empfehlungs-Block, Helper-Funktionen
- Dashboard-CSS: `.score-*`, `.faktor-*`, `.li-score` Klassen
- `TEMPLATE-csc_bewerbungen-INSERT.sql` (intern-Repo): `score_gesamt` aus RETURNING

## Noch offen

### 1. Portal-FAQ (Pre-Offline-Stand des Bewerbungsformulars)
`index.html` aktuell = Offline-Hinweis (213 Zeilen, Commit `a83fa6e`). Der echte
Bewerbungsbogen liegt im Vorgaenger-Commit `a83fa6e~1` und enthaelt **noch**
einen FAQ-Block ueber den Score (`a83fa6e~1:index.html` Z. 3824–3836, beginnt
mit "Der Portal berechnet automatisch einen Punktewert von 0 bis 100 (Score)…").

**Wann erledigen:** beim Portal-Slimdown (Branch `portal-slimdown-2026-05-28`),
sobald der Portal-Code restored wird. Der FAQ-Block muss komplett raus, weil der
Score nicht mehr existiert.

### 2. DB Hard-Cleanup (Variante B — Spalten NULLen, Index/View/Function droppen)
Aktuell sind nur die Trigger DISABLED. Noch ausstehend (separater SQL-Block,
nach erfolgreichem Dashboard-Deploy):

```sql
-- View ohne score_gesamt
CREATE OR REPLACE VIEW csc_bewerbungen_uebersicht AS
  SELECT b.id, b.bewerber_token, b.status, b.eingegangen_am,
         b.vorname, b.nachname, b.email, b.rollen, b.verein_id,
         v.name AS verein_name, v.ort AS verein_ort
  FROM csc_bewerbungen b
  JOIN csc_vereine v ON v.id = b.verein_id;

-- Index droppen (sinnlos auf NULL-Spalte)
DROP INDEX IF EXISTS idx_csc_bewerbungen_score;

-- Trigger + Trigger-Function droppen
DROP TRIGGER IF EXISTS csc_compute_score_on_insert ON csc_bewerbungen;
DROP TRIGGER IF EXISTS csc_compute_score_on_update ON csc_bewerbungen;
DROP FUNCTION IF EXISTS csc_trigger_compute_score();
DROP FUNCTION IF EXISTS csc_compute_bewerbung_score(uuid);

-- Score-Werte NULLen (Variante B — Spalten BEHALTEN, Daten weg)
UPDATE csc_bewerbungen SET score_gesamt = NULL, score_pro_rolle = NULL
  WHERE score_gesamt IS NOT NULL OR score_pro_rolle IS NOT NULL;
```

Reihenfolge: erst Dashboard deployen (Code laeuft ohne Score), dann obigen
Block ausfuehren. Backup vorher (Supabase Dashboard → Backups).

### 3. Variante C (Spalten droppen) — spaeter, GF-Entscheidung
Variante B ist reversibel (Spalten bleiben). Endgueltiger Drop ist eine
rechtliche Entscheidung fuer GF / Datenschutzbeauftragten — nicht Teil dieses
Commits.

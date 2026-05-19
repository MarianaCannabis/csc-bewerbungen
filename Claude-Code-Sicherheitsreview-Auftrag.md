# Sicherheits-Review CSC-Bewerbungssystem — Auftrag für Claude Code

## Inhalt dieses Ordners

Dieser Ordner enthält das gesamte zu prüfende System:

- `csc-bewerbungen/` — die Web-App: öffentlicher Bewerbungsbogen
  (`index.html`), internes Dashboard (`dashboard/`), Bewerber-Status-Seite
  (`status/`) und zwei Planungs-Rechner.
- `datenbank/` — die SQL-Skripte (Schema, RLS, Funktionen, Härtungen) und die
  Edge Functions (`edge-functions/`).
- `doku/` — vorhandene Sicherheits- und Datenschutz-Dokumentation als Kontext.

Backend ist Supabase (Postgres + RLS + Edge Functions + Storage).

## Auftrag

Führe einen vollständigen Sicherheits-Review dieses Projekts durch, Schwerpunkt
Datensicherheit. Geh systematisch die folgenden Punkte durch und gib am Ende
eine Befundliste mit Schweregrad (kritisch / mittel / niedrig) und konkretem
Fix-Vorschlag.

1. **Geheimnisse im Client-Code** — steht im Browser-Code irgendwo mehr als der
   öffentliche Supabase-`anon`-Key? Service-Role-Key, Passwörter, API-Keys?
2. **Row Level Security** — hat jede `csc_*`-Tabelle und `storage.objects` RLS
   aktiv? Decken die Policies wirklich alles ab, oder gibt es Lecks (z. B. eine
   SELECT-Policy ohne Verein-Filter)? Prüfe besonders `csc_bewerbungen`,
   `csc_vertragsdaten`, `csc_bewerbung_anhaenge`.
3. **anon-Rechte** — hat `anon` nur die minimal nötigen Tabellen-GRANTs
   (INSERT Bewerbung + Anhang, SELECT Vereine) und nichts darüber hinaus?
4. **SECURITY DEFINER-Funktionen** — ist jede solche Funktion sauber gegen
   Missbrauch geschützt (Token- oder Rollenprüfung), und ist überall
   `search_path` gepinnt?
5. **Edge Functions** — bleibt der Service-Role-Key serverseitig? Werden
   Eingaben validiert, ist der Token-Zugang sauber, ist CORS angemessen?
6. **Token-Handling** — der `bewerber_token` ist der einzige Schlüssel zur
   Status-Seite und zu den Vertragsdaten. Wird er sicher erzeugt und behandelt?
7. **XSS / Injection** — werden Nutzereingaben (Namen, Nachrichten etc.), die
   per `innerHTML` gerendert werden, konsequent escaped? Das bitte gründlich,
   über alle HTML-Dateien.
8. **DSGVO / Datenminimierung** — werden nur nötige Daten erhoben und sauber
   getrennt (besonders die Vertragsdaten)?
9. **Die Rechner** — sie haben kein Backend, nur LocalStorage. Stimmt das, und
   gibt es dort trotzdem ein Datenleck-Risiko?

## Baseline — schon abgehärtet, bitte verifizieren statt neu suchen

- Eine frühere RLS-Policy `csc_bewerbungen_select_self_token` (machte alle
  Bewerbungen für `anon` lesbar) wurde entfernt — bestätige, dass sie weg ist.
- `anon`-GRANTs wurden auf das Minimum reduziert.
- Die Storage-SELECT-Policy hat einen Verein-Filter bekommen, DELETE nur für
  Admins.
- `csc_vertragsdaten` ist eine eigene Tabelle mit RLS (Lesen/Löschen nur
  Admin), Schreiben nur über eine token- und statusgeprüfte
  SECURITY-DEFINER-Funktion.

Der Ordner `doku/` (besonders `SICHERHEITS_STATUS.md`) beschreibt den
bisherigen Stand — du kannst dagegen prüfen.

## Wichtig

Die SQL-Dateien sind Migrations-Skripte. Du kannst prüfen, ob sie in sich
stimmig und sicher formuliert sind — ob sie auch in der **Live-Datenbank**
ausgeführt wurden, lässt sich nur in Supabase selbst verifizieren.

## Live-Datenbank zusätzlich prüfen (optional)

Wenn der Review auch den echten DB-Zustand abdecken soll, kann Claude Code
einen Postgres-/Supabase-MCP-Server bekommen. Dann lassen sich Policies und
Rechte direkt in der Datenbank abfragen statt nur die Skripte zu lesen.

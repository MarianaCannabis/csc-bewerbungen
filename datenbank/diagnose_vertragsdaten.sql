-- ============================================================================
--  Diagnose: warum zeigt das Dashboard nicht alle Vertragsdaten?
--  Im Supabase SQL-Editor ausführen und die Ausgabe zurückmelden.
-- ============================================================================

-- 1) Welche Spalten hat die Tabelle csc_vertragsdaten wirklich?
--    Erwartet: 21 Spalten (id, bewerbung_id, 17 Datenfelder, 2 Zeitstempel).
--    Nur ~9 -> die umfangreiche Migration wurde noch nicht ausgeführt.
SELECT string_agg(column_name, ', ' ORDER BY ordinal_position) AS spalten,
       count(*) AS anzahl
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'csc_vertragsdaten';

-- 2) Welche save_vertragsdaten-Funktion existiert?
--    Erwartet: genau eine, Signatur "text, jsonb".
--    "text, text, text, text, text, text" -> alte Version, Migration fehlt.
SELECT proname,
       pg_get_function_identity_arguments(oid) AS signatur
FROM pg_proc
WHERE proname = 'save_vertragsdaten';

-- 3) Letzte gespeicherte Zeile — zeigt, welche Felder tatsächlich befüllt sind
--    (NULL = wurde nicht gespeichert, leerer Text = Bewerber ließ es leer).
SELECT *
FROM csc_vertragsdaten
ORDER BY aktualisiert_am DESC NULLS LAST
LIMIT 1;

-- 4) Schema-Cache der API neu laden (PostgREST).
--    Falls die Spalten unter 1) vorhanden sind, das Dashboard sie aber
--    trotzdem nicht zeigt, kennt die API die neuen Spalten noch nicht.
--    Diese Zeile lädt den Cache neu — schadet nie, hilft in diesem Fall.
NOTIFY pgrst, 'reload schema';

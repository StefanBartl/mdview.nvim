# Roadmap

## Wichtig

- Statt Browser "TempApp" soll aktuelle Browsersitzung genutzt werden
- Nach dem stop mus unbedingt der Prozess

## Allgemein

1. `TODO-Comments` lösen
2. Stark modularisieren
3. Es muss sichergestellt sein, dass `npm` installiert und im Pfad verfügbar ist, ansonsten muss früh eine Meldung ausgegeben werden.
4. In mdview.config ein Feld open_on_start (default true) und open_url (overrides) hinzufügen.
5. Falls man feinere Kontrolle möchte: nur öffnen, wenn vim.fn.has("gui_running") == 1 oder vim.env.DISPLAY gesetzt ist.
6. In Debug-Modus optional vim.notify("Opening browser: " .. url).
7. Fokus nach MDViewStart geht in den Browser

---

## Testing

- Line Diff: `tests\mdview\util\diff.md`

---

## Client

---

## Server

- In server wss-Broadcast: vor dem client.send(payload) try/catch pro-client, damit ein fehlerhafter Client nicht ganze Broadcast-Loop abbricht.
- Client: createTransport so erweitern, dass import.meta.env.VITE_WS_URL akzeptiert wird — einfach per .env konfigurierbar.

---

## bonus features

- `open_preview_tab` in "./lua/mdview/usercommands/autostart" ermöglichen um die ausgabe im nvim-Tab anstatt im Browser anzuzeigen
- Rendern einer Datei in einen übergebenen Pfad mit optionalen setzten des cwd wie `:MDViewStart C:/Users/bartl/test.md {cwd?}`
- Starten einer Datei mit manuell geetzten cwd  `:MDViewStart cwd="c:/Users/bartl/"`
- Schließen des Browser Tabs soll auch MDView beenden
- Wie behandlen wir, wenn MDViewOpen bei mehreren Datein ausgeführt wird? Sessions machen ?

---

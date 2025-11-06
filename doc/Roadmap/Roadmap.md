# Roadmap

## BUGS

  1. health-Modul
  ==============================================================================
  mdview:                                       require("mdview.health").check()

  - ERROR Failed to run healthcheck for "mdview" plugin. Exception:
    [string "require("mdview.health").check()"]:1: attempt to call field 'check' (a nil value)

  2. Statt Browser "TempApp" soll aktuelle Browsersitzung genutzt werden
  3. Abklären: Sollten wir nicht WebSocketStream nutzen? (wenn möglich, also vorher `(!(if "WebsocketStream" in self))`)

## Allgemein

  1. `TODO-Comments` lösen
  3. Es muss sichergestellt sein, dass `npm` installiert und im Pfad verfügbar ist, ansonsten muss früh eine Meldung ausgegeben werden.
  4. In mdview.config ein Feld open_on_start (default true) und open_url (overrides) hinzufügen.
  5. Falls man feinere Kontrolle möchte: nur öffnen, wenn vim.fn.has("gui_running") == 1 oder vim.env.DISPLAY gesetzt ist.
  6. In Debug-Modus optional vim.notify("Opening browser: " .. url).
  7. Fokus nach MDViewStart geht in den Browser
  8. Enstchieden: Was kommtr in die logdatei, was wir in nvim ausgegeben ?
  9. Wie sollen sich die Node.js-Server verhalten, wenn nvim geschlossen wurde, ohnedas `MDViewStop` aufgerufen wurde ?
  10. Es ist extrem wichtig, dass sich, wenn möglich, neue Tabs den bestehenden Prozess anhängen.
  11. Wen nman da brpwser ab schlließt, muss damit umgegangen werden: Am besten schließt sic auch die app
  12. Ist es so bzw. möglich, dass ein Server mehrere CWD's hostet?

-

## Clean & Nice Code

  1. jeder Parameter muss typisiert werden
  2. Stark modularisieren

## Testing

  1. Line Diff: `tests\mdview\util\diff.md`

---

## Client

---

## Server

  1. In server wss-Broadcast: vor dem client.send(payload) try/catch pro-client, damit ein fehlerhafter Client nicht ganze Broadcast-Loop abbricht.
 Client: createTransport so erweitern, dass import.meta.env.VITE_WS_URL akzeptiert wird — einfach per .env konfigurierbar.

---

## bonus features

  1. `open_preview_tab` in "./lua/mdview/usercommands/autostart" ermöglichen um die ausgabe im nvim-Tab anstatt im Browser anzuzeigen
  2. Rendern einer Datei in einen übergebenen Pfad mit optionalen setzten des cwd wie `:MDViewStart C:/Users/bartl/test.md {cwd?}`
  3. Starten einer Datei mit manuell geetzten cwd `:MDViewStart cwd="c:/Users/bartl/"`
  4. Schließen des Browser Tabs soll auch MDView beenden
  5. Wie behandlen wir, wenn MDViewOpen bei mehreren Datein ausgeführt wird? Sessions machen ?
  6. Bidirektionales Scrolling, midestens aber von nvim zu browser

---

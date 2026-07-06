# Roadmap

## BUGS

  1. ~~health-Modul: `require("mdview.health").check()` fehlte~~ — behoben.
     Ursache: `lua/mdview/health.lua` exportierte nur `health_report`, nicht `check()`;
     eine bessere `check()`-Implementierung lag ungenutzt in `plugin/health.lua`
     (falscher Pfad, wird von `:checkhealth` nie geladen). Jetzt in
     `lua/mdview/health.lua` zusammengeführt und an die native Go/Rust-Architektur
     angepasst (prüft curl/tar statt Node/npm).

  2. Statt Browser "TempApp" soll aktuelle Browsersitzung genutzt werden
  3. Abklären: Sollten wir nicht WebSocketStream nutzen? (wenn möglich, also vorher `(!(if "WebsocketStream" in self))`)

## Allgemein

  1. `TODO-Comments` lösen
  3. ~~Es muss sichergestellt sein, dass `npm` installiert und im Pfad verfügbar ist~~ — obsolet seit dem Go/Rust-Rewrite:
     Endnutzer brauchen kein npm/Node mehr; `mdview.adapter.install` lädt die fertige
     Server-Binary + Client-Bundle von GitHub Releases. `:checkhealth` prüft stattdessen
     `curl`/`tar`.
  4. In mdview.config ein Feld open_on_start (default true) und open_url (overrides) hinzufügen.
  5. Falls man feinere Kontrolle möchte: nur öffnen, wenn vim.fn.has("gui_running") == 1 oder vim.env.DISPLAY gesetzt ist.
  6. In Debug-Modus optional vim.notify("Opening browser: " .. url).
  7. Fokus nach MDViewStart geht in den Browser
  8. Enstchieden: Was kommtr in die logdatei, was wir in nvim ausgegeben ?
  9. Wie soll sich der mdview-server-Prozess verhalten, wenn nvim geschlossen wurde, ohne dass `MDViewStop` aufgerufen wurde ?
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

  1. ~~In server wss-Broadcast: vor dem client.send(payload) try/catch pro-client~~ — behoben in
     `native/server/internal/relay/registry.go`: `Registry.Broadcast` sammelt Send-Fehler pro
     Verbindung statt die Fan-out-Schleife abzubrechen (siehe `TestRegistry_BroadcastCollectsSendErrorsWithoutStoppingFanout`).

---

## Cross-Platform audit (personal checklist item 4)

  Found and removed two dead modules with dangerous module-load-time side effects
  (executed unconditionally the instant anything `require`d them, with no caller
  opting in):
  - `lua/mdview/utils/ports/cleanup/{cross_os,simple}.lua` — force-killed (`Stop-Process
    -Force` / `kill -9`) *any* process listening on port 43219, unconditionally, at
    module load. Unreferenced anywhere; deleted. The Go relay's `FindFreePort` already
    handles port conflicts by picking the next free port instead of killing anything.
  - `lua/mdview/adapter/runner_showlogs.lua` — called `log.setup({ debug = true, ... })`
    at module load, forcing debug mode on globally for anyone who ever required it;
    also referenced a nonexistent `cfg.LOG_BUF_NAME` field. Unreferenced anywhere
    (superseded by `bindings/usrcmds/show_weblogs.lua`); deleted.

  Also fixed a real bug in `lua/mdview/adapter/log.lua`: `local cfg require(...)` was
  missing its `=`, so `cfg` was always `nil` and `debug`/`log_buffer_name` config
  overrides were silently ignored. Fixed, and switched to reading the config live
  instead of caching a stale snapshot at require-time (adapter.log loads before
  `setup()` runs).

## filetree.nvim cross-check

  Checked whether mdview.nvim has features worth extracting into `filetree.nvim`
  (per the personal plugin checklist). Nothing applicable found: mdview.nvim is a
  markdown preview tool with no file-tree/file-navigation surface of its own.

## bonus features

  1. `open_preview_tab` in "./lua/mdview/usercommands/autostart" ermöglichen um die ausgabe im nvim-Tab anstatt im Browser anzuzeigen
  2. Rendern einer Datei in einen übergebenen Pfad mit optionalen setzten des cwd wie `:MDViewStart C:/Users/bartl/test.md {cwd?}`
  3. Starten einer Datei mit manuell geetzten cwd `:MDViewStart cwd="c:/Users/bartl/"`
  4. Schließen des Browser Tabs soll auch MDView beenden
  5. Wie behandlen wir, wenn MDViewOpen bei mehreren Datein ausgeführt wird? Sessions machen ?
  6. Bidirektionales Scrolling, midestens aber von nvim zu browser

---

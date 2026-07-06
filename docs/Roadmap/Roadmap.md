# Roadmap

## BUGS

  1. ~~health-Modul: `require("mdview.health").check()` fehlte~~ — behoben.
     Ursache: `lua/mdview/health.lua` exportierte nur `health_report`, nicht `check()`;
     eine bessere `check()`-Implementierung lag ungenutzt in `plugin/health.lua`
     (falscher Pfad, wird von `:checkhealth` nie geladen). Jetzt in
     `lua/mdview/health.lua` zusammengeführt und an die native Go/Rust-Architektur
     angepasst (prüft curl/tar statt Node/npm).

  2. ~~Statt Browser "TempApp" soll aktuelle Browsersitzung genutzt werden~~ — behoben:
     `build_args_for_browser.lua`'s Profilverzeichnis war bei jedem Aufruf ein frischer
     `fn.tempname()` — jedes `:MDViewStart` erzeugte einen komplett neuen, isolierten
     Browser-Prozess statt die laufende mdview-Session wiederzuverwenden. Jetzt ein fester,
     persistenter Pfad unter `stdpath("data")/mdview/browser-profile`, über Aufrufe hinweg
     wiederverwendet (Chrome/Firefox öffnen bei gleichem Profil i. d. R. einen neuen Tab im
     bestehenden Fenster statt eines neuen Prozesses). Bleibt isoliert vom echten
     Standard-Browserprofil des Nutzers — nur das eigene "Wegwerf-Session"-Verhalten bei
     jedem einzelnen Aufruf ist behoben.
  3. Abklären: Sollten wir nicht WebSocketStream nutzen? — Nein: WebSocketStream (Streams-API
     über WebSocket, Backpressure-fähiges Lesen) lohnt sich für sehr hohen Durchsatz oder
     große binäre Payloads. mdview.nvim überträgt kleine Text-Updates (ein Markdown-Puffer)
     pro Broadcast — der bestehende einfache `ws.send`/`onmessage`-Pfad (Go: `gorilla`-artiges
     WS über `nhooyr.io/websocket`, Client: natives `WebSocket`) ist hier ausreichend und
     deutlich einfacher zu debuggen. Nicht weiter verfolgt.
  4. ~~`:MDViewStop` löschte sich selbst + `:MDViewOpen`~~ — behoben, kritischer Bug.
     `stop.lua`'s `M.stop()` rief `usercmds_registry.detach_all()` auf; `:MDViewOpen`
     und `:MDViewStop` waren als "non-persistent" über diese Registry registriert
     (`bindings/usrcmds/init.lua`'s `attach_non_persistent()`), aber nichts hat sie je
     neu registriert. Nach dem ersten `:MDViewStop` waren beide Commands für den Rest
     der Neovim-Session weg. Fix: alle vier Usercmds sind jetzt "persistent" (einmal
     bei `setup()` registriert, nie torn down — Autocmds haben weiterhin einen
     echten Attach/Detach-Lifecycle, Usercmds nicht). `usercmds_registry.lua`
     dadurch komplett ungenutzt, gelöscht.

## Allgemein

  1. `TODO-Comments` lösen
  3. ~~Es muss sichergestellt sein, dass `npm` installiert und im Pfad verfügbar ist~~ — obsolet seit dem Go/Rust-Rewrite:
     Endnutzer brauchen kein npm/Node mehr; `mdview.adapter.install` lädt die fertige
     Server-Binary + Client-Bundle von GitHub Releases. `:checkhealth` prüft stattdessen
     `curl`/`tar`.
  4. ~~In mdview.config ein Feld open_on_start (default true) und open_url (overrides) hinzufügen.~~
     `browser.browser_autostart` deckt `open_on_start` bereits ab (gleiche Semantik, existierte
     schon). Neu hinzugefügt: `browser.open_url` — statische Override-URL, greift in
     `launcher.resolve_browser_url()` nach dem per-call `opts.browser_url`, vor der
     berechneten Key/Token-URL.
  5. ~~Falls man feinere Kontrolle möchte: nur öffnen, wenn vim.fn.has("gui_running") == 1 oder
     vim.env.DISPLAY gesetzt ist.~~ — behoben: `launcher.has_display()` (Windows/macOS immer
     true, Unix prüft `DISPLAY`/`WAYLAND_DISPLAY`), gated hinter neuem
     `browser.require_display` (default true). Ohne Display: Warnung statt sinnlosem
     Browser-Spawn-Versuch.
  6. ~~In Debug-Modus optional vim.notify("Opening browser: " .. url).~~ — behoben, `launcher.lua`
     loggt das jetzt vor jedem `browser_adapter.open()`-Aufruf (`log.debug`, gated auf
     `debug_preview` wie alle anderen Debug-Logs).
  7. Fokus nach MDViewStart geht in den Browser — vermutlich bereits gegeben (neues
     Chrome/Firefox `--app`-Fenster wird vom OS normalerweise automatisch fokussiert), aber
     nicht zuverlässig aus Neovim heraus erzwingbar (kein plattformübergreifendes API dafür,
     ohne fragile OS-spezifische Hacks wie `wmctrl`). Nicht weiter verfolgt.
  8. Entschieden: Was kommt in die Logdatei, was wird in nvim ausgegeben? `adapter/log.lua`
     hält zwei unabhängige Sinks: ein In-Memory-Ringpuffer (max. 2000 Zeilen, sichtbar via
     `:MDViewShowWebLogs`) und optional eine Logdatei (nur wenn `log.setup({file_path=...})`
     explizit gesetzt wird — nicht standardmäßig aktiv). UI-Echo (`vim.api.nvim_echo`) nur bei
     `debug=true`.
  9. ~~Wie soll sich der mdview-server-Prozess verhalten, wenn nvim geschlossen wurde, ohne dass
     `MDViewStop` aufgerufen wurde?~~ — echter Bug gefunden und behoben: `vim_leave.lua`'s
     `VimLeavePre`-Autocmd war mit `pattern = defaults.ft_pattern` registriert.
     `VimLeavePre` ist aber ein globales Lifecycle-Event, kein Buffer-Event — Neovim matcht
     `pattern` gegen den *aktuell fokussierten* Buffer im Moment des Events. War der zuletzt
     aktive Buffer keine Markdown-Datei, feuerte die Cleanup-Logik NIE, und der
     mdview-server-Prozess blieb verwaist. Fix: `pattern` entfernt — feuert jetzt immer.
     Verifiziert (Test: aktueller Buffer = `.lua`-Datei, Autocmd feuert trotzdem).
  10. ~~Es ist extrem wichtig, dass sich, wenn möglich, neue Tabs den bestehenden Prozess
     anhängen.~~ — bereits durch die Architektur gegeben: der Go-Relay gruppiert Verbindungen
     per Dokument-Pfad (`Registry` in `native/server/internal/relay/registry.go`), nicht per
     Tab/Prozess. `:MDViewOpen` (siehe `mdview.open()`) verbindet sich immer mit der
     laufenden Session statt einen neuen Server zu starten.
  11. ~~Wenn man den Browser abschließt, muss damit umgegangen werden: Am besten schließt sich
     auch die App.~~ — behoben: neues `browser.stop_on_browser_exit` (default true).
     `launcher.lua`'s `on_exit`-Callback ruft jetzt `require("mdview.bindings.usrcmds.stop").stop()`
     auf, wenn der Browser-Prozess endet (z. B. Fenster/Tab geschlossen). `stop()`'s
     bestehende `state`-Guards machen einen doppelten Stop-Aufruf (z. B. wenn `:MDViewStop`
     selbst den Browser schließt und dadurch erneut `on_exit` auslöst) ungefährlich.
  12. ~~Ist es so bzw. möglich, dass ein Server mehrere CWD's hostet?~~ — ja, bereits gegeben.
      Der laufende Relay-Prozess ist an keine CWD/Projekt-Root gebunden: Rooms werden per
      absolutem Datei-Pfad geschlüsselt (`native/server/internal/relay/registry.go`), der
      Server selbst liest nie Dateien vom Datenträger für den Markdown-Inhalt (der kommt per
      HTTP-POST von Neovim) — nur der statische Client-Bundle-Pfad (`--web-root`) ist fix und
      unabhängig davon, welche Datei gerade angezeigt wird. Ein einziger laufender Server kann
      also Markdown-Dateien aus beliebig vielen, nicht verwandten Verzeichnissen gleichzeitig
      bedienen, ohne Neustart. `server_cwd`/`cwd=...` betrifft nur das Arbeitsverzeichnis des
      Server-*Prozesses* selbst, nicht welche Dateien er anzeigen kann.

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

- In filetree.nvim könnte man usrcmds / keymaps andenken,die wenn auf einer file node die markdown ist steht,dass man diese dann via mdview direkt aus dem filetree aus öffnen kann

## bonus features

  1. `open_preview_tab` in "./lua/mdview/usercommands/autostart" ermöglichen um die ausgabe im nvim-Tab anstatt im Browser anzuzeigen —
     eigener Task ausgelagert (architektonisch eigenständig: die aktuelle Pipeline rendert +
     sanitized ausschließlich im Browser via Rust/WASM, siehe |mdview-security|; ein
     nvim-Tab-Preview bräuchte einen komplett separaten Rendering-Pfad, kein kleiner Zusatz).
  2. ~~Rendern einer Datei in einen übergebenen Pfad mit optionalem cwd:
     `:MDViewStart C:/Users/bartl/test.md {cwd?}`~~ — behoben: `:MDViewStart` akzeptiert jetzt
     `nargs="*"`, parsed Datei-Pfad + optionales `cwd=...` in beliebiger Reihenfolge.
  3. ~~Starten einer Datei mit manuell gesetztem cwd: `:MDViewStart cwd="c:/Users/bartl/"`~~ —
     behoben, gleicher Mechanismus wie oben (`cwd=` ohne Datei-Arg nutzt den aktuellen Buffer).
  4. ~~Schließen des Browser Tabs soll auch MDView beenden~~ — behoben, siehe BUGS #11
     (`browser.stop_on_browser_exit`).
  5. Wie behandeln wir, wenn MDViewOpen bei mehreren Dateien ausgeführt wird? Sessions machen? —
     bereits gelöst: jede Datei bekommt ihren eigenen WS-"Room" (Key = normalisierter Pfad) im
     Go-Relay; `:MDViewOpen` öffnet für die aktuelle Datei einen Tab in genau diesem Room, ohne
     andere offene Dateien/Tabs zu beeinflussen. Keine zusätzliche Session-Verwaltung nötig.
  6. ~~Bidirektionales Scrolling, mindestens aber von nvim zu browser~~ — nvim-zu-Browser-Richtung
     umgesetzt (Browser-zu-nvim bleibt offen, war nicht gefordert: "mindestens aber..."):
     Neuer `POST /scroll?key=...&token=...`-Endpoint (Go), der Cursor-Zeile+Gesamtzeilen als
     `"<line>/<total>"` per `Registry.BroadcastEphemeral` an die Raum-Mitglieder verteilt — bewusst
     NICHT über `Broadcast`, da das `LastPayload` überschreiben und neu beitretende Tabs mit der
     Scroll-Position statt dem echten Dokument seeden würde (getestet:
     `TestRegistry_BroadcastEphemeralReachesRoomWithoutTouchingLastPayload`). Nachrichten sind mit
     `\x01`-Präfix getaggt (nicht in getipptem Markdown möglich), damit der Client zwischen
     Content-Update und Scroll-Ping unterscheiden kann, ohne einen JSON-Envelope einzuführen.
     Neues `bindings/autocmds/scroll_sync.lua` sendet auf `CursorMoved`/`CursorMovedI`, throttled
     (`scroll_sync_throttle_ms`, default 150ms), gated hinter `scroll_sync` (default true). Client
     scrollt proportional (`line/total`-Verhältnis), kein Source-Line-Mapping in comrak nötig —
     bewusst kein Pixel-genauer Abgleich, sondern ein robuster, einfacher erster Wurf.
     Nebenbefund beim Verifizieren: `#mdview-root` hatte gar kein CSS und war dadurch nicht
     scrollbar (wuchs nur mit dem Inhalt) — `index.html` bekam ein Minimal-Stylesheet
     (`height:100vh; overflow-y:auto`), sonst wäre auch `scrollTop` grundsätzlich wirkungslos
     gewesen. End-to-End mit echtem Browser (Playwright-Preview) verifiziert.

---

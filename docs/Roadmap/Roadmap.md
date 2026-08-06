# Roadmap

> **Offene Aufgaben** stehen (nach Aufwand sortiert) in [`TASKS.md`](./TASKS.md).
> Diese Datei ist das Log der **erledigten** Punkte samt Begründungen.
> Vor-Rewrite-Dokumente (`Meilensteine*.md`, `WebTransportAPI/*`,
> `Server/utils/codec.md`, `checkpoints/01_checkpoint.md`) tragen ein
> OUTDATED-Banner und sind nur noch Historie.

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

  5. ~~`:MDViewStart` startete den Server, aber danach passierte nichts: kein Browser, kein
     Initial-Push, und jede Buffer-Änderung spammte nur "server ready after X ms, attempt 1"~~ —
     behoben, eine Kette von fünf Bugs (per E2E-Test gegen das echte Binary verifiziert):
     - **`ws_client.wait_ready` rief im Erfolgsfall nie `cb(true)` auf** — nur ein Echo.
       Der komplette On-Ready-Block im Launcher (Initial-Push + Browser-Open) und jeder
       Live-Push liefen dadurch ins Leere; das Echo pro Tastendruck war der ganze Effekt.
       Fix: `cb(true)` + Readiness-Cache (`M._ready`, kein curl /health pro Tastendruck mehr;
       Reset via `reset_ready()` bei Stop/Respawn).
     - **Launcher-On-Ready crashte an `live_push.attach()` ohne Gruppe** ("Invalid 'group': 0")
       — direkt VOR Initial-Push und Browser-Open; wurde erst durch den cb-Fix überhaupt
       erreichbar. Fix: redundanten Aufruf entfernt (Autocmds sind beim Spawn schon
       registriert) + `live_push.attach(nil)` abgehärtet (kein `group or 0` mehr).
     - **Token-Mismatch**: `launcher.start` rief `server_args.resolve()` erneut auf (rotiert
       den Session-Token in state), während `runner.start_server` den BESTEHENDEN Prozess
       (mit dem alten Token) zurückgab → alle /update- und /ws-Requests liefen als stille
       403s (curl exit 0 bei HTTP-Fehlern). Fix: laufender Prozess wird wiederverwendet,
       resolve/Token-Rotation nur beim tatsächlichen Spawn.
     - **`state.proc_is_running()` prüfte das nichtexistente Feld `M.proc`** statt
       `M.runner.proc` → immer false. Fix: korrektes Feld + Handle-Validität.
     - **`resolve_browser_url` bevorzugte `browser.dev_server_port` (43220, Vite)
       bedingungslos** — in Produktion lauscht dort nichts; selbst ein geöffneter Browser
       hätte ins Leere gezeigt. Fix: echter Backend-Port (`vim.g.mdview_server_port`);
       Dev-Port nur noch über `vim.g.mdview_dev_port` (wird ausschließlich gesetzt, wenn der
       Runner eine echte Vite-Zeile in stdout geparst hat). `browser.dev_server_port` als
       Config-Feld entfernt.
     Außerdem: Debug-Defaults (`debug`, `debug_plugin`, `debug_preview`) von true auf false —
     Server-stdout-Echos und Per-Push-Notifications sind jetzt opt-in statt Dauer-Spam.

  6. ~~Nach dem obigen Fix: `:MDViewStart` → `:MDViewStop` → `:MDViewStart` crashte mit
     "Invalid 'group': 216", und danach sagte jeder weitere `:MDViewStart` nur noch
     "server already running" ohne Browser~~ — behoben, drei Folgebugs:
     - **`autocmds.teardown()` löschte die Augroup per id, aber `lib.nvim`'s `get_augroup`
       cached diese id** und gab sie beim Neustart erneut zurück — nun eine gelöschte,
       ungültige id → `nvim_create_autocmd` crashte (`bufenter.lua`). Fix:
       `autocmds.init` erzeugt die Augroup direkt via `nvim_create_augroup(name, {clear=true})`
       (immer gültig, kein Stale-Cache); der redundante `_attached_groups`-Dedup in
       `live_push` entfernt.
     - **Half-State nach dem Crash**: `state.set_server(proc)` lief VOR `autocmds.attach()`,
       das dann crashte → `server` blieb gesetzt → "already running" gegen eine nie fertig
       gestartete Session. Fix: `set_server` erst nach erfolgreichem `attach`.
     - **`:MDViewStart` bei laufendem Server tat nichts Sinnvolles** (nur "already running").
       Häufigster Grund für erneutes `:MDViewStart` ist aber ein geschlossenes Browserfenster.
       Fix: der "already running"-Zweig öffnet jetzt die Preview-Oberfläche neu
       (`mdview.open()` bzw. Tab-Preview) statt nur zu meckern.
  7. ~~Chrome öffnete ein "komisches" Fenster ohne Taskleisten-Icon und ohne Toolbar~~ —
     `--app=`-Modus war schuld (chromeloses App-Fenster). Fix: `build_args_for_browser`
     nutzt jetzt `--new-window` → normales Browserfenster (Taskleisten-Icon, Adressleiste).
     Das isolierte Profil bleibt — es ist genau das, was `stop_on_browser_exit`/
     `browser_autoclose` zuverlässig macht (ein Start in den bereits laufenden Browser des
     Nutzers würde sofort forken+exiten, Schließen wäre nicht detektierbar).
  > **AUFGELÖST (2026-07-26) für #8–#10: `:MDView detach` wurde entfernt.** Die drei Bugs
  > waren allesamt Symptome desselben Grundproblems — ein detachter, headless, stdio-loser
  > nvim ist ein schlechter Langzeit-Host: input-poll-getriebene Loop (→ #8 Timing), kein
  > File-Watch/`--listen` (→ #9 kein Live-Push, statischer Snapshot), kein Tab-Close-Observer
  > (→ #10). Da die detachte Instanz zudem nie editiert wird, existiert der behauptete
  > Live-Buffer-Vorteil faktisch nicht → `detach` war von `:MDView standalone` vollständig
  > dominiert. Konsequenz: `detach`, `detach.lua` und das `User MDViewSessionEnded`-Event
  > entfernt; die Terminal-Wrapper (`mdview-bg.*`) feuern jetzt `:MDView standalone`. Die
  > untenstehende Analyse bleibt als Begründung stehen. Siehe
  > `docs/Roadmap/KONZEPT_headless_und_standalone.md` und `docs/standalone.md`.

  8. **`:MDView detach` / `scripts/mdview-bg.ps1`: Browser-Tab öffnet sich gar nicht oder erst
     mit mehreren Minuten Verzögerung** (beobachtet unter Windows), obwohl der Relay selbst
     sauber hochkommt (Health-Check ok, initialer Push kommt an). ~~Noch offen~~ — nächster
     Ansatzpunkt beim Wiederaufnehmen:
     - Unterschied zu `:MDView standalone` (öffnet dort zuverlässig sofort): `standalone`s
       Browser-Open läuft direkt im Go-Relay-Binary (`native/server/open.go`, einzelner
       `rundll32.exe url.dll,FileProtocolHandler`-Aufruf, kein Neovim beteiligt). `detach`
       und `mdview-bg.ps1` laufen beide über eine **headless, komplett stdio-lose, detachte**
       Neovim-Instanz (`nvim --headless -u scripts/minimal_init.lua -c "MDView start"`), in
       der sowohl der `/health`-Poll (`ws_client.lua`'s `http_get`, curl per
       `vim.fn.jobstart`, alle 200ms bis zu 10s) als auch das eigentliche Öffnen
       (`mdview.adapter.browser`'s `open_default`, ebenfalls `vim.fn.jobstart`) verkettet
       über Neovims Job-Control laufen statt über einen einzelnen direkten Prozess-Spawn.
     - Manuelle Nachstellung des exakten `detached.spawn`-Aufrufs (`uv.spawn` mit
       `stdio = {nil,nil,nil}`, `detached = true`) hat in einem Testlauf funktioniert
       (Health-Check, WebSocket-Connect, Render kamen durch) — der Code ist also nicht
       grundsätzlich falsch, das Timing ist nur unzuverlässig.
     - Verdacht: `vim.fn.jobstart()`-Aufrufe aus einer headless+detachten (kein Stdio,
       keine Konsole) Neovim-Instanz auf Windows sind unter bestimmten Bedingungen deutlich
       langsamer als aus einer normalen interaktiven Instanz — und `detach`/`mdview-bg.ps1`
       verketten davon gleich drei (Health-Poll → Initial-Push → Browser-Open), statt wie
       `standalone` mit einem einzigen nativen Spawn auszukommen. Noch nicht isoliert, woran
       es genau liegt (auf der ursprünglichen Testmaschine so beobachtet, in einer anderen
       Umgebung nicht reproduziert — also eher Neovim-Job-Control/Windows-spezifisch als ein
       Logikfehler im Plugin-Code selbst).
     - Möglicher Fix, falls sich das bestätigt: den Browser-Open-Schritt im `detach`-Pfad
       genauso wie bei `standalone` direkt nativ spawnen (z.B. über ein kleines Go-Hilfsmittel
       oder einen direkten `uv.spawn`-Aufruf aus Lua) statt über `vim.fn.jobstart` aus der
       headless Instanz heraus.
  9. **`:MDView detach`: Live-Push/Scroll-Sync erreichen die detachte Preview nicht, wenn die
     Datei aus einer separaten/neuen Neovim-Instanz bearbeitet wird** — per Test verifiziert
     (README.md von einer zweiten, unabhängigen headless-nvim-Instanz aus editiert+gespeichert;
     im Relay-Log der detachten Session kam danach keinerlei neue Aktivität an). Ursache: die
     detachte Instanz hält ihren eigenen Buffer-Stand ab dem Spawn-Zeitpunkt; es gibt keinen
     Datei-Watcher (kein `vim.loop.new_fs_event`, kein `checktime`/`autoread`-Timer — geprüft,
     nichts davon existiert im Code) und `detach.lua` startet den Kindprozess ohne `--listen`,
     man kann sich also auch nicht nachträglich per `nvim --server`/`--remote` an genau diese
     Instanz anhängen, um "in ihr" weiterzuschreiben. Damit ist der in der Modul-Doku
     (`bindings/usrcmds/detach.lua`) beschriebene Kernunterschied zu `standalone` ("live buffer
     push … weil ein echtes Neovim es treibt") im derzeit einzig erreichbaren Nutzungsmuster
     (Datei extern weiterbearbeiten) faktisch nicht gegeben. Möglicher Fix: `detach.lua` einen
     `--listen`-Socket mitgeben (Adresse in der Start-Notify ausgeben), damit man sich per
     `nvim --server <addr> --remote` wieder anhängen kann — oder einen Datei-Watcher ergänzen,
     der bei externer Änderung neu liest und pusht.
  10. **`:MDView detach`: Schließen des Preview-Tabs beendet die detachte Neovim-Instanz NICHT
      von selbst**, obwohl die Start-Notify genau das verspricht ("stop it by closing the
      preview tab, or kill the pid"). Per Code-Analyse verifiziert: `User MDViewSessionEnded`
      wird im gesamten Code nur an genau einer Stelle gefeuert (`bindings/usrcmds/stop.lua`,
      innerhalb von `:MDViewStop`) — nichts beobachtet ein Tab-Close und feuert das Event
      automatisch. Der Default-`browser.open_mode` ("default", von `minimal_init.lua` nicht
      überschrieben) liefert laut `adapter/browser/init.lua` explizit "a handle with no
      job_id: mdview can't programmatically close it" — `on_exit`/`stop_on_browser_exit`
      sind dort No-Ops. Und selbst wenn man `:MDViewStop` manuell auslösen wollte: die
      detachte Instanz hat keinen `--listen`-Socket, ist also von außen gar nicht erreichbar.
      Fazit: aktuell bleibt als einziger funktionierender Weg, eine `:MDView detach`-Instanz
      zu beenden, tatsächlich nur `Stop-Process`/`taskkill` auf die PID — der "Tab schließen"-
      Teil der Notify-Message ist derzeit irreführend. Hängt mit Punkt 9 zusammen (`--listen`
      wäre auch hier die Voraussetzung für einen sauberen Fix, z.B. per periodischem
      Health-Poll gegen den Relay: wenn keine Clients mehr verbunden sind, selbst `:MDViewStop`
      auslösen).
  11. ~~`:MDView start` (der normale, nicht-standalone/detach-Pfad) hatte keine Möglichkeit,
      eine lokal gebaute Relay/Client-Version zu verwenden~~ — behoben. `server_args.resolve()`
      rief bislang immer `install.ensure_binary()`/`install.ensure_client_bundle()` auf (feste
      Bindung an `install.version`, Default `v0.2.0`); es gab **keinen** Override, weder als
      Config-Feld noch als Env-Var — obwohl genau das schon in einer früheren Doku-Notiz als
      `dev = { binary_path, web_root }` beschrieben war (dieses Feld existierte nirgends im
      Code). Da `install.version`s Pin älter ist als die `/control`-Route (Overlay/Zoom/Cursor
      Live-Control), liefen diese Live-Befehle über den normalen Start-Pfad ins Leere — fire-
      and-forget POST gegen eine Route, die die gepinnte Release-Binary noch nicht kennt, ohne
      Fehler oder Effekt. Fix: neues `dev.binary_path` / `dev.web_root` (mit Fallback auf
      `$MDVIEW_DEV_BINARY` / `$MDVIEW_DEV_WEB_ROOT`, aus demselben Grund wie bei `standalone`
      — ein detachter Prozess lädt keine Lua-Config) in `lua/mdview/adapter/server_args.lua`;
      dokumentiert in `docs/configuration.md`. End-to-End verifiziert: lokal gebaute Relay
      (aktueller `main`-Branch) über `:MDView start` gestartet, `/control` mit Zoom-/Overlay-/
      Cursor-Payloads direkt gepostet → alle drei `204`.

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
  2. ~~Lokale Bildlinks im gerenderten HTML zeigen kaputte Icons~~ — behoben. Der
     WASM-Renderer (`comrak`) erzeugte für `![alt](bild.png)` schon immer
     korrektes `<img>`-Markup (siehe `source_map_does_not_pollute_image_alt`
     in `native/wasm-render/src/lib.rs`), aber der einzige `http.FileServer`
     zeigte auf `web_root` (das Client-Bundle), nie auf das Verzeichnis des
     gerade angezeigten Dokuments — ein relativer Bildpfad daneben lief
     serverseitig ins Leere. Neu: `GET /asset?key=&path=&token=` in
     `native/server/main.go`, aufgelöst relativ zu dem Verzeichnis, das
     `handleDoc` pro Session mitschreibt (`Registry.SetDocDir`/`DocDir`) —
     die Basis kommt also ausschließlich vom vertrauenswürdigen lokalen
     Neovim-Prozess, nie vom Browser-Tab. Pfad-Traversal-Schutz
     (`filepath.Clean` + Containment-Check) und eine Endungs-Allowlist
     (nur Bildformate) engen die Route bewusst ein, statt ein generischer
     Datei-Server zu sein. Client-seitig schreibt `src/client/render/
     localImages.ts` (`resolveLocalImages`, nach jedem Render aufgerufen,
     analog zu `markExternalLinks`) relative `<img src>` auf diese Route um;
     `http(s)://`/`data:`-Quellen bleiben unangetastet. Aus
     `images.nvim`s `docs/ROADMAP/CROSS-PLUGIN.md` (mdview.nvim-Eintrag).
     Tests: `main_test.go` (Traversal/Allowlist/Token/Session), `registry_test.go`
     (`SetDocDir`/`DocDir`), `tests/client/localImages.test.ts`.

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

  1. ~~`open_preview_tab` ermöglichen um die Ausgabe im nvim-Tab anstatt im Browser
     anzuzeigen~~ — umgesetzt, bewusst komplett entkoppelt von der Browser/WASM-Pipeline
     (kein HTML, kein Relay/WebSocket, kein externes Tool wie `glow`):
     - Neues `lua/mdview/adapter/preview_tab.lua`: öffnet einen eigenen Tab mit einem
       read-only Mirror-Buffer des Quell-Buffers, gehighlighted via Neovims Markdown-
       Treesitter-Parser (Fallback auf Vims mitgeliefertes `syntax=markdown`, falls der
       Parser fehlt — nie ungehighlighted). Live-Sync über eine eigene, selbstständige
       Autocmd-Gruppe (`bindings/autocmds/preview_tab_sync.lua`), komplett unabhängig vom
       `:MDViewStart`/`:MDViewStop`-Lifecycle — funktioniert eigenständig ohne laufenden Server.
     - Neuer Command `:MDViewPreviewTab` (Toggle, funktioniert standalone).
     - Neues Config-Feld `open_preview_tab` (default false): wenn true, öffnet
       `:MDViewStart` den Tab-Preview statt des Browsers (Relay/WASM-Pipeline läuft trotzdem
       im Hintergrund weiter, `:MDViewOpen` kann den Browser jederzeit nachträglich öffnen).
     - Bewusst gegen `glow`/externe Renderer entschieden: kein zusätzlicher optionaler
       Toolchain-Kandidat, keine Subprozess-Ausführung für dieses Feature — passt besser
       zum "minimale Angriffsfläche"-Ziel des Rewrites als ein weiteres opt-in External-Tool.
     - End-to-End verifiziert (headless nvim: Toggle open/close, Treesitter-Highlighting,
       Live-Sync bei Buffer-Änderung, korrektes Cleanup beim Schließen).
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
  2. ~~`:MDView blanklines [on|off|toggle]`: Leerzeilen im Quelltext 1:1 als sichtbaren
     Abstand in der Preview zeigen, statt CommonMarks Standardverhalten (jede Folge von
     Leerzeilen wird zu genau einem Absatzabstand komprimiert)~~ — umgesetzt. Kein
     Rust/Comrak-Änderungsbedarf: `data-sourcepos="startLine:col-endLine:col"` wird bereits
     unbedingt auf jedem Top-Level-Block emittiert (`native/wasm-render/src/lib.rs`,
     `options.render.sourcepos = true`), unabhängig vom Source-Map-Parameter fürs Caret.
     Neue Client-Seite `src/client/render/blankLines.ts`: berechnet je zwei aufeinander-
     folgenden Top-Level-Blöcken die tatsächliche Leerzeilen-Zahl aus der Sourcepos-Lücke
     und fügt bei Bedarf einen reinen Spacer-`<div>` mit `height: Nem` VOR dem Block ein
     (additiv, damit das Theme-eigene Absatz-/Heading-Margin unangetastet bleibt statt
     überschrieben zu werden). `docModel.ts`s `BlockPos` um `endLine` erweitert. Wired wie
     Zoom/Cursor/Overlay: `browser.preserve_blank_lines` (default `false`) in `DEFAULTS.lua`,
     `?blanklines=1` in `launcher.lua`s URL-Aufbau (nur bei `true`, wie bei `zoom`), neues
     `lua/mdview/bindings/usrcmds/blanklines.lua` + Route in `usrcmds/init.lua`, Live-Update
     über denselben `/control`-Kanal (`{blankLines: bool}` — Wire-Key bleibt bewusst anders
     als der Config-Feldname, wie bei `cursor_marker` → `cursor`). End-to-End verifiziert:
     lokal gebaute Relay über `:MDView start` (mit dem neuen `dev.binary_path`/`dev.web_root`,
     siehe „Allgemein"), `:MDView blanklines on` → Notify bestätigt + `/control` mit
     `{"blankLines":true}` direkt gepostet → `204`. Lua-Testsuite (24/24) und ESLint auf den
     neuen/geänderten Client-Dateien grün; `tsc --noEmit` bricht nur an der in diesem Worktree
     fehlenden generierten `wasm-render`-Datei ab (nie gebaut, unabhängig von dieser Änderung)
     — sonst keine Typfehler.

---

## UX: Browser-Modi & Rendering-Look

  1. ~~Preview öffnete in einem separaten Fenster (nicht als Tab im normalen Browser) und ohne
     die Extensions/das Aussehen des Nutzers~~ — neues `browser.open_mode` (default `"default"`):
     - `"default"`: öffnet die URL im Standard-Browser des Nutzers als neuer Tab (via
       `vim.ui.open`, Fallback `start`/`open`/`xdg-open`) — seine Extensions, sein Theme, sein
       Profil. Trade-off: mdview kann den Tab nicht programmatisch schließen, daher sind
       `browser_autoclose`/`stop_on_browser_exit` in diesem Modus No-ops (markdown-preview.nvim-
       Ansatz, siehe `markdown_preview/browser/tab.md`).
     - `"isolated"`: bisheriges Verhalten (eigenes Profil, eigener Prozess) — Auto-Close
       funktioniert zuverlässig, aber ohne die Extensions/Lesezeichen des Nutzers.
     Kooperatives Schließen im default-Modus (WS-`close`-Event → `window.close()`) ist als
     Mittel-Task in `TASKS.md` erfasst.
  2. ~~Gerendertes Markdown sah schlecht aus (Client-HTML hatte praktisch kein CSS)~~ — eingebautes
     GitHub-artiges Theme (`src/client/themes/github.css`, Light/Dark automatisch via
     `prefers-color-scheme`, plus `data-theme`-Pinning). Theme-Auswahl über `browser.theme`
     (an den Client als `?theme=` übergeben) + lazy-geladene `THEME_LOADERS` in `main.ts` →
     weitere Themes sind ein CSS-File + ein Map-Eintrag. End-to-End im echten Browser verifiziert
     (Headings mit Border, Codeblöcke, Tabellen, Blockquotes, Dark-Mode). Die „externe
     Renderer-Website"-Idee ist als opt-in-Task in `TASKS.md` festgehalten (mit Privacy-Hinweis:
     widerspricht dem loopback-only-Modell) — `browser.open_url` ist bereits die Escape-Hatch für
     eine beliebige URL.
  3. ~~GFM-Task-Listen (`- [ ]` / `- [x]`) wurden ohne Checkbox gerendert~~ — ammonia strippte die
     `<input>`-Elemente (nicht in der Default-Allowlist). Sanitizer in
     `native/wasm-render/src/lib.rs` erlaubt jetzt gezielt `<input>` mit nur `type`/`checked`/
     `disabled` (Checkboxen können kein JS ausführen, kein Form-Kontext, `formaction`/Event-Handler
     werden weiterhin entfernt — mit Test `strips_dangerous_input_attributes`).

---

## Performance: `:MDView start` vs. `:MDView standalone`

  1. ~~Entlastet `standalone` Neovim gegenüber dem normalen `start`-Pfad?~~ — ja, klar und
     drastisch gemessen. Kontrollierter Benchmark: 150 diskrete Edits an einer Markdown-Datei,
     einmal durch `:MDView start` (Edits über `nvim_buf_set_lines` in derselben Instanz, die auch
     den Relay-Kindprozess hält), einmal durch `:MDView standalone` (dieselben 150 Edits extern
     per `Add-Content` direkt auf die Datei, während die startende nvim-Instanz nur noch daneben
     steht). Gemessen wurde die CPU-Zeit des nvim.exe-Prozesses selbst (`Get-Process
     .TotalProcessorTime`-Delta, Windows).
     - **`start`: 1875 ms CPU** für 150 Edits (~2.9s Wall-Zeit) — nvim war den Großteil der Zeit
       aktiv CPU-beschäftigt.
     - **`standalone`: 0 ms CPU** — komplett unverändert, obwohl dieselben 150 Edits an der
       beobachteten Datei ankamen.
     - Ursache gefunden: `bindings/autocmds/live_push.lua` throttelt **nicht** — jedes
       `TextChanged`/`TextChangedI` (potenziell jeder Tastenanschlag im Insert-Modus) spawnt
       sofort einen eigenen `curl`-Prozess via `vim.fn.jobstart` für den vollen Buffer-Push. Bei
       `standalone` gibt es diesen Pfad überhaupt nicht — der Relay beobachtet die Datei mit
       seinem eigenen (Go-seitigen) Watcher, komplett entkoppelt von Neovim.
     - ~~Mögliche Folge-Optimierung: `live_push` throttlen (ähnlich `scroll_sync_throttle_ms`)~~ —
       umgesetzt. Neues `live_push_throttle_ms` (default 150, wie `scroll_sync_throttle_ms`) in
       `lua/mdview/bindings/autocmds/live_push.lua`. Anders als Scroll-Sync's Throttle (das einen
       zu frühen Ping einfach verwirft — unkritisch für eine transiente Scroll-Position) darf ein
       Content-Push nicht verworfen werden, sonst bliebe die Preview dauerhaft veraltet, ohne dass
       etwas anderes einen Resync auslöst. Deshalb: Push innerhalb des Throttle-Fensters wird nicht
       verworfen, sondern auf einen einzelnen Trailing-Timer verschoben (max. `throttle_ms`
       Verzögerung, kein Neu-Terminieren bei jedem weiteren Tastenanschlag) — der letzte Stand
       kommt garantiert an. `BufWritePost`s Full-Push beim Speichern bleibt bewusst ungedrosselt
       (seltener, dient als Resync-Punkt). Verifiziert mit demselben Benchmark wie oben: 150 Edits
       unter `:MDView start` fielen von 1875ms auf **937,5ms CPU** (−50%). Lua-Testsuite (24/24)
       weiterhin grün.

# mdview — Test-, Log- & Prüfkonzept

> **Stand: Go-Relay + Rust/WASM-Client.** Serverseitiges Rendering, der
> Node-Dev-Server (`npm run dev:server`), der Vite-Proxy auf `43220` und der
> `/render`-Endpoint existieren **nicht mehr**. Dieses Dokument beschreibt, wie
> man die einzelnen Komponenten testet und wie die Logs/Diagnose an Dritte (oder
> an einen Assistenten) übergeben werden können.

Die Komponenten:

1. **Neovim-Plugin (Lua)** — startet/stoppt den Relay, öffnet den Browser,
   sendet Buffer-Updates und Scroll-Pings.
2. **Go-Relay** (`native/server/`) — Transport von Rohtext, token-gated,
   bindet nur an `127.0.0.1`.
3. **Rust/WASM-Client** (`src/client/` + `native/wasm-render/`) — rendert und
   sanitisiert Markdown im Browser.

---

## 1. Schnellster Weg: `:MDViewDiagnose`

Ein einziger Befehl erzeugt einen vollständigen Zustandsbericht **über alle
Komponenten** und öffnet ihn in einem neuen Tab. Die Datei kann direkt
weitergegeben / eingelesen werden.

```vim
:MDViewDiagnose            " schreibt nach stdpath('log')/mdview-diagnostics.txt
:MDViewDiagnose C:\tmp\d.txt   " optional: eigener Pfad
```

Der Bericht enthält:

- **Environment** — nvim-Version, OS, `is_windows`, Display/GUI vorhanden
- **Dependencies** — `lib.nvim` (hard dependency), `curl`, `tar`, `vim.ui.open`
- **Install cache** — ob Server-Binary und Client-Bundle gecached sind (+ Pfade)
- **Config** — `server_port`, `open_preview_tab`, `scroll_sync`,
  `browser.open_mode/theme/browser_autostart/require_display`
- **Running session** — läuft der Prozess? attached? Token gesetzt? erkannter
  Port? **Live-`GET /health`-Probe**
- **Browser-URL**, die geöffnet würde (inkl. `key`/`token`/`theme`)
- **Recent internal log** — die letzten Einträge des `mdview.log`-Ring-Buffers

> Der interne Ring läuft über `lib.nvim.logger` (`mdview.log`). `notify`-Level
> ist per Default aus; Debug-Notifications erscheinen nur bei
> `config.debug_preview = true`.

---

## 2. Browser-Logs ohne DevTools: `/clientlog`

Der Client meldet seine eigenen Diagnosen (fehlendes key/token,
Verbindungsfortschritt, Transport-Fehler, erster erfolgreicher Render,
Render-Fehler) per `POST /clientlog?token=…` an den Relay. Der Relay druckt
jede Zeile als `[client] …` auf stdout — und die Lua-Runner-Schicht fängt den
Relay-stdout ein, sodass die Zeilen in **`:MDViewShowWebLogs`** und im
`:MDViewDiagnose`-Bericht auftauchen. Kein DevTools-Öffnen nötig.

```vim
:MDViewShowWebLogs   " Relay-stdout inkl. [client]-Zeilen
```

Manueller Smoke-Test des Sinks (Relay muss laufen):

```sh
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST "http://localhost:<port>/clientlog?token=<token>" --data "hallo"
# 204, und im Relay-stdout / :MDViewShowWebLogs:  [client] hallo
```

Optionale manuelle Browser-Konsolen-Checks (nur zur Fehlersuche):

```js
console.log("location", location.href);          // key/token/theme in der URL?
new WebSocket(`ws://${location.host}/ws${location.search}`); // readyState === 1 ?
```

---

## 3. Komponenten einzeln testen

### Neovim / Plugin

```vim
:checkhealth mdview   " Runtime-Infos, Dependency-Status
:MDViewStart          " Relay starten + Browser öffnen
:MDViewStop           " Relay stoppen
:MDViewShowWebLogs    " Relay-stdout + [client]-Logs
:MDViewDiagnose       " Vollbericht (siehe oben)
```

Headless-Smoke-Test (CI-nah), lädt lib.nvim ins rtp:

```sh
# Spec unter tests/lua/smoke_spec.lua (plenary/busted-Stil)
"/c/Program Files/Neovim/bin/nvim" --headless -u NONE -i NONE \
  --cmd "set rtp+=.,../lib.nvim" \
  -c "luafile tests/lua/smoke_spec.lua" -c "qa!"
```

### Go-Relay

Siehe [../server/Testanweisugen.md](../server/Testanweisugen.md) für
Endpoint-für-Endpoint-Tests. Automatisiert:

```sh
cd native/server && go vet ./... && go test ./...
```

### Rust/WASM-Client

```sh
cd native/wasm-render && cargo test        # Rendering + XSS-Payload-Tests
# Root: Client-Bundle bauen (Rust -> WASM -> Vite)
export CARGO="$HOME/.cargo/bin/cargo.exe"; export PATH="$HOME/.cargo/bin:$PATH"
npm run build
npx tsc -p tsconfig.json && npx eslint "src/**/*.{ts,tsx,js}"
```

---

## 4. Prozess auf einem Port beenden

```powershell
# Windows (PowerShell)
Get-NetTCPConnection -LocalPort 43219 -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force }
```

```sh
# Linux/macOS
lsof -i :43219 && kill -9 <PID>
```

> Es laufen keine `node.exe`-Prozesse mehr — der Relay ist eine einzelne native
> Binary. `EADDRINUSE`/Zombie-Node-Hinweise aus älteren Doku-Ständen sind
> obsolet; bei belegtem Port genügt das Beenden der obigen Binary.

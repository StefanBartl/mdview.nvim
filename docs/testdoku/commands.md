# mdview — testing, logging & inspection concept

> **Status: Go relay + Rust/WASM client.** Server-side rendering, the Node dev
> server (`npm run dev:server`), the Vite proxy on `43220` and the `/render`
> endpoint **no longer exist**. This document describes how to test the
> individual components and how the logs/diagnostics can be handed to a third
> party (or to an assistant).

The components:

1. **The Neovim plugin (Lua)** — starts/stops the relay, opens the browser,
   sends buffer updates and scroll pings.
2. **The Go relay** (`native/server/`) — transports raw text, token-gated,
   binds only to `127.0.0.1`.
3. **The Rust/WASM client** (`src/client/` + `native/wasm-render/`) — renders and
   sanitises markdown in the browser.

---

## 1. The quickest route: `:MDView diagnose`

A single command produces a complete state report **across all components** and
opens it in a new tab. The file can be handed on / read in directly.

```vim
:MDView diagnose               " writes to stdpath('log')/mdview-diagnostics.txt
:MDView diagnose C:\tmp\d.txt  " optional: your own path
```

The report contains:

- **Environment** — nvim version, OS, `is_windows`, whether a display/GUI exists
- **Dependencies** — `lib.nvim` (a hard dependency), `curl`, `tar`, `vim.ui.open`
- **Install cache** — whether the server binary and client bundle are cached (+ paths)
- **Config** — `server_port`, `open_preview_tab`, `scroll_sync`,
  `browser.open_mode/theme/browser_autostart/require_display`
- **Running session** — is the process running? attached? is the token set? the
  detected port? a **live `GET /health` probe**
- **The browser URL** that would be opened (including `key`/`token`/`theme`)
- **Recent internal log** — the last entries of the `mdview.log` ring buffer

> The internal ring runs through `lib.nvim.logger` (`mdview.log`). The `notify`
> level is off by default; debug notifications appear only with
> `config.debug_preview = true`.

---

## 2. Browser logs without DevTools: `/clientlog`

The client reports its own diagnostics (a missing key/token, connection
progress, transport errors, the first successful render, render errors) to the
relay via `POST /clientlog?token=…`. The relay prints every line as
`[client] …` to stdout — and the Lua runner layer captures the relay's stdout,
so the lines show up in **`:MDView weblogs`** and in the `:MDView diagnose`
report. No need to open DevTools.

```vim
:MDView weblogs   " relay stdout including the [client] lines
```

A manual smoke test of the sink (the relay must be running):

```sh
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST "http://localhost:<port>/clientlog?token=<token>" --data "hello"
# 204, and in the relay stdout / :MDView weblogs:  [client] hello
```

Optional manual browser-console checks (for troubleshooting only):

```js
console.log("location", location.href);          // key/token/theme in the URL?
new WebSocket(`ws://${location.host}/ws${location.search}`); // readyState === 1 ?
```

---

## 3. Testing the components individually

### Neovim / the plugin

```vim
:checkhealth mdview   " runtime info, dependency status
:MDView start         " start the relay + open the browser
:MDView stop          " stop the relay
:MDView weblogs       " relay stdout + [client] logs
:MDView diagnose      " the full report (see above)
```

A headless smoke test (close to CI), loading lib.nvim into the rtp:

```sh
# Spec under TESTS/lua/smoke_spec.lua (plenary/busted style)
"/c/Program Files/Neovim/bin/nvim" --headless -u NONE -i NONE \
  --cmd "set rtp+=.,../lib.nvim" \
  -c "luafile TESTS/lua/smoke_spec.lua" -c "qa!"
```

### The Go relay

See [../server/Testanweisugen.md](../server/Testanweisugen.md) for
endpoint-by-endpoint tests. Automated:

```sh
cd native/server && go vet ./... && go test ./...
```

### The Rust/WASM client

```sh
cd native/wasm-render && cargo test        # rendering + XSS payload tests
# From the root: build the client bundle (Rust -> WASM -> Vite)
export CARGO="$HOME/.cargo/bin/cargo.exe"; export PATH="$HOME/.cargo/bin:$PATH"
npm run build
npx tsc -p tsconfig.json && npx eslint "src/**/*.{ts,tsx,js}"
```

---

## 4. Killing a process on a port

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

> There are no `node.exe` processes any more — the relay is a single native
> binary. The `EADDRINUSE`/zombie-Node notes from older documentation states are
> obsolete; if the port is occupied, terminating the binary above is enough.

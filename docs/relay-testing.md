# Testing the relay by hand

For working on the Go relay (`native/server/`) or on the browser bridge.
`go test ./...` covers the automated half; this page is the manual half —
driving each endpoint with `curl` so a failure can be pinned to one hop
instead of "the preview is blank".

Running the *plugin's* test suites is [Development](development.md#tests).
Reading logs during normal use is
[Operations](FEATURES/OPERATIONS.md) and [WORKFLOW.md](WORKFLOW.md).

> **Architecture note.** mdview does **not** render Markdown server-side.
> The relay transports only **raw text** to the browser tabs; rendering and
> sanitising happen exclusively in the Rust/WASM client. There is therefore
> no `/render` endpoint and no Node dev server. Instructions elsewhere that
> expect JSON `{ html }` responses describe a version that no longer exists.

## Endpoints

All functional endpoints are **token-gated** (`?token=<session>`), except
`/health` and the static client. The token is generated per session in Lua
(`mdview.adapter.server_args`) and passed to the binary as `--token`.

| Method | Path         | Auth           | Purpose                                            |
|--------|--------------|----------------|----------------------------------------------------|
| GET    | `/health`    | —              | Liveness probe, returns `ok`                       |
| POST   | `/update`    | token + `key`  | The raw text of a document to all tabs of the `key`|
| POST   | `/scroll`    | token + `key`  | Scroll ping `"<line>/<total>"` (ephemeral)         |
| POST   | `/clientlog` | token          | Browser diagnostics → stdout `[client] …`          |
| GET    | `/ws`        | token + `key` + Origin | WebSocket upgrade, one room per `key`      |
| GET    | `/`          | —              | The static client bundle (HTML/JS/WASM)            |

## 1) Starting the relay binary manually

After the first `:MDView start` the binary lives in the install cache:

```
# Windows
$env:LOCALAPPDATA\nvim-data\mdview\bin\v0.1.0\mdview-server_windows_amd64.exe
# Linux/macOS
~/.local/share/nvim/mdview/bin/v0.1.0/mdview-server_<os>_<arch>
```

Build it straight from the repo and start it with a fixed port + token:

```sh
npm run build:go   # -> native/server/mdview-server.exe on Windows, mdview-server elsewhere
cd native/server && ./mdview-server.exe --port 45999 --token testtok123 --web-root ../../dist/client
# stdout: "Running on http://localhost:45999"  (Lua matches exactly this line)
```

(The hand-written `go build -o mdview-server.exe .` that stood here was the
workaround for `build:go` writing an extension-less name on Windows; the script
picks the suffix itself since 2026-08-30.)

## 2) Checking health

```sh
curl -sS http://localhost:45999/health   # expected: ok
```

## 3) Sending raw text to a room (`/update`)

`key` identifies the document (in practice the absolute file path).
Several browser tabs with the same `key` form one room.

```sh
curl -sS -X POST "http://localhost:45999/update?token=testtok123&key=test1" \
  --data-binary "# Hello from the relay"
# expected: HTTP 204 No Content; connected tabs of the key re-render the text
```

A wrong/missing token ⇒ **403**, a missing `key` ⇒ **400**.

## 4) Checking the browser diagnostics sink (`/clientlog`)

The client reports its own diagnostics — a missing key/token, connection
progress, transport errors, the first successful render, render errors — to
the relay, which prints each line as `[client] …` on stdout. The Lua runner
captures that stdout, so those lines also surface in `:MDView weblogs` and in
the `:MDView diagnose` report. That is the reason you rarely need DevTools.

```sh
curl -sS -o /dev/null -w "%{http_code}\n" \
  -X POST "http://localhost:45999/clientlog?token=testtok123" --data "hello"
# expected: 204, and on the relay stdout:  [client] hello
```

If you do end up in the browser console, these two answer most of it:

```js
console.log("location", location.href);          // key/token/theme in the URL?
new WebSocket(`ws://${location.host}/ws${location.search}`); // readyState === 1 ?
```

## 5) WebSocket room isolation

Two clients with different `key`s must **not** see each other.
`go test ./...` in `native/server/internal/relay` covers that automatically
(room assignment, origin rejection, token validation). Manually with `websocat`:

```sh
websocat "ws://localhost:45999/ws?token=testtok123&key=test1" \
  -H "Origin: http://localhost:45999"
# without a valid Origin header -> "forbidden origin" (DNS rebinding protection)
```

## 6) A headless smoke test of the Lua side

Close to what CI runs, with `lib.nvim` put on the runtimepath by hand:

```sh
nvim --headless -u NONE -i NONE \
  --cmd "set rtp+=.,../lib.nvim" \
  -c "luafile TESTS/lua/smoke_spec.lua" -c "qa!"
```

## 7) Cleaning up / port occupied

```sh
# Windows (PowerShell)
Get-NetTCPConnection -LocalPort 45999 -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force }
# Linux/macOS
lsof -i :45999 && kill -9 <PID>
```

> The relay binds exclusively to `127.0.0.1`, so there are no
> firewall/interface special cases. The relay is a single native binary —
> there are no stray `node.exe` processes to hunt down any more; killing the
> process above is enough.

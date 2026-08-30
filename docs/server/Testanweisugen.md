# Server test instructions (Go relay)

> **Architecture note.** mdview **no longer** renders markdown server-side.
> The Go relay (`native/server/`, shipped as a platform-specific binary)
> transports only **raw text** to the browser tabs; rendering and sanitising
> happen exclusively in the Rust/WASM client. There is therefore **no `/render`
> endpoint** any more and **no Node dev server** (`npm run dev:server` and the
> Vite proxy on 43220 are removed). Older instructions expecting JSON
> `{ html }` responses are invalid.

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

After the first `:MDViewStart` the binary lives in the install cache:

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

```sh
curl -sS -o /dev/null -w "%{http_code}\n" \
  -X POST "http://localhost:45999/clientlog?token=testtok123" --data "hello"
# expected: 204, and on the relay stdout:  [client] hello
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

## 6) Cleaning up / port occupied

```sh
# Windows (PowerShell)
Get-NetTCPConnection -LocalPort 45999 -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force }
# Linux/macOS
lsof -i :45999 && kill -9 <PID>
```

> The relay binds exclusively to `127.0.0.1`, so there are no firewall/interface
> special cases as there were with the old Node server.

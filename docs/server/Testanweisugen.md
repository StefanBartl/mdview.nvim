# Server-Testanweisungen (Go-Relay)

> **Architektur-Hinweis.** mdview rendert Markdown **nicht** mehr serverseitig.
> Der Go-Relay (`native/server/`, ausgeliefert als plattformspezifische Binary)
> transportiert nur **Rohtext** an die Browser-Tabs; gerendert und sanitisiert
> wird ausschließlich im Rust/WASM-Client. Es gibt daher **keinen `/render`-
> Endpoint** mehr und **keinen Node-Dev-Server** (`npm run dev:server`, Vite-
> Proxy auf 43220 sind entfernt). Alte Anleitungen, die JSON-`{ html }`-
> Antworten erwarten, sind ungültig.

## Endpoints

Alle Nutz-Endpoints sind **token-gated** (`?token=<session>`), außer `/health`
und dem statischen Client. Der Token wird pro Session in Lua generiert
(`mdview.adapter.server_args`) und als `--token` an die Binary übergeben.

| Methode | Pfad         | Auth           | Zweck                                             |
|---------|--------------|----------------|---------------------------------------------------|
| GET     | `/health`    | —              | Liveness-Probe, liefert `ok`                      |
| POST    | `/update`    | token + `key`  | Rohtext eines Dokuments an alle Tabs des `key`    |
| POST    | `/scroll`    | token + `key`  | Scroll-Ping `"<line>/<total>"` (ephemer)          |
| POST    | `/clientlog` | token          | Browser-Diagnose → stdout `[client] …`            |
| GET     | `/ws`        | token + `key` + Origin | WebSocket-Upgrade, Room pro `key`         |
| GET     | `/`          | —              | statisches Client-Bundle (HTML/JS/WASM)           |

## 1) Relay-Binary manuell starten

Die Binary liegt nach dem ersten `:MDViewStart` im Install-Cache:

```
# Windows
$env:LOCALAPPDATA\nvim-data\mdview\bin\v0.1.0\mdview-server_windows_amd64.exe
# Linux/macOS
~/.local/share/nvim/mdview/bin/v0.1.0/mdview-server_<os>_<arch>
```

Direkt aus dem Repo bauen und mit festem Port + Token starten:

```sh
cd native/server && go build -o mdview-server.exe .
./mdview-server.exe --port 45999 --token testtok123 --web-root ../../dist/client
# stdout: "Running on http://localhost:45999"  (Lua matcht genau diese Zeile)
```

## 2) Health prüfen

```sh
curl -sS http://localhost:45999/health   # erwartet: ok
```

## 3) Rohtext an einen Room senden (`/update`)

`key` identifiziert das Dokument (in der Praxis der absolute Dateipfad).
Mehrere Browser-Tabs mit demselben `key` bilden einen Room.

```sh
curl -sS -X POST "http://localhost:45999/update?token=testtok123&key=test1" \
  --data-binary "# Hallo aus dem Relay"
# erwartet: HTTP 204 No Content; verbundene Tabs des key rendern den Text neu
```

Falscher/fehlender Token ⇒ **403**, fehlender `key` ⇒ **400**.

## 4) Browser-Diagnose-Sink prüfen (`/clientlog`)

```sh
curl -sS -o /dev/null -w "%{http_code}\n" \
  -X POST "http://localhost:45999/clientlog?token=testtok123" --data "hello"
# erwartet: 204, und auf dem Relay-stdout erscheint:  [client] hello
```

## 5) WebSocket-Room-Isolation

Zwei Clients mit unterschiedlichem `key` dürfen sich **nicht** gegenseitig sehen.
Automatisiert deckt das `go test ./...` in `native/server/internal/relay` ab
(Room-Zuordnung, Origin-Ablehnung, Token-Validierung). Manuell mit `websocat`:

```sh
websocat "ws://localhost:45999/ws?token=testtok123&key=test1" \
  -H "Origin: http://localhost:45999"
# ohne gültige Origin-Header -> "forbidden origin" (DNS-Rebinding-Schutz)
```

## 6) Aufräumen / Port belegt

```sh
# Windows (PowerShell)
Get-NetTCPConnection -LocalPort 45999 -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force }
# Linux/macOS
lsof -i :45999 && kill -9 <PID>
```

> Der Relay bindet ausschließlich an `127.0.0.1`, daher gibt es keine
> Firewall-/Interface-Sonderfälle wie beim alten Node-Server.

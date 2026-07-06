# Commands

## Generell

- Einen folgender Befehle ausführen:

```sh
# 1
Test-NetConnection -ComputerName localhost -Port 43219
# 2
$body = Get-Content .\tests\test.md -Raw
Invoke-RestMethod -Uri 'http://localhost:43219/render?key=test' -Method Post -Headers @{ 'Content-Type' = 'text/markdown' } -Body $body
# 3&4
node tests/test-ws.js ws://localhost:43219/ws
node tests/test-ws.js ws://localhost:43220/ws

curl -X POST "http://localhost:43220/render?key=test" -H "Content-Type: text/markdown" --data-binary "$(cat tests/test.md)"

# send file content as text/markdown using PowerShell native cmdlet
Invoke-RestMethod -Uri 'http://localhost:43219/render?key=test' -Method Post -ContentType 'text/markdown' -Body (Get-Content .\tests\test.md -Raw)

# use --% to stop PowerShell from parsing the remaining arguments
curl.exe --% -v -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary @tests/test.md

# pipe file content into curl.exe; use --% to stop PowerShell parsing
Get-Content .\tests\test.md -Raw | curl.exe --% -v -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary @-
```

sollte JSON mit `html` zurückgeben.

---

### server-Prozess wirklich auf dem Port läuft

  ```powershell
  Test-NetConnection -ComputerName localhost -Port 43219
  ```
* Wenn `wscat` / `node test-ws.js` anzeigt `Connected` → WS ist erreichbar.
* Wenn `Invoke-RestMethod` fehlschlägt, prüfe Windows-Firewall / Antivirus evtl. Blockierung.
* Nutze `curl.exe -v ...` um raw HTTP traffic zu sehen (mehrere Tests oben).

---


## Browser-Konsole

- quick manual checks:
Wenn das readyState === 1 wird, ist WS verbunden. Wenn Connection closed before receiving a handshake response kommt, ist Proxy/Backend nicht erreichbar oder geschlossen — mit obigem Launcher-Patch sollte das nicht mehr vorkommen.

```js
console.log("location", location.href);
new WebSocket((location.protocol === 'https:' ? 'wss' : 'ws') + '://' + location.host + '/ws');
```
- Upgrade Check
    Öffne DevTools → Network → Reload (F5) → beobachte /ws Upgrade und 101 Switching Protocols.
    Falls handshake fehlschlägt: prüfe backend logs ([mdview-server] Running on http://localhost:...) und ob runner die Ports in vim.g.mdview_server_port / vim.g.mdview_dev_port schreib

---

## Websocket

### wscat

```sh
# install wscat globally once (requires npm)
npm install -g wscat

# from powershell try to open websocket to backend directly:
wscat -c ws://localhost:43219/ws

# or try via vite port (should proxy)
wscat -c ws://localhost:43220/ws
```

Wenn wscat verbindet to 43219 but client can't, proxy problem; if neither connects, backend WebSocket server not bound/accepting upgrades.

### node websocket test

Node test script for websockets (cross-platform, run with node)

Speichern als `tests/test-ws.js` und mit `node tests/test-ws.js ws://localhost:43219/ws` ausführen.

---


## server

- Ports beenden:

```sh
# powershell
netstat -ano | findstr 43219
taskkill /PID <PID> /F
Get-NetTCPConnection -LocalPort 43219 -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -ne 0 } | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }

Stop-Process -Name node -Force

# Linux/macOS:
lsof -i :43219
kill -9 <PID>

# Server-Health:
curl -sS http://localhost:43219/health
# Erwartet: ok

# Server-Index prüfen (liefert HTML / client bootstrap):
curl -sS http://localhost:43219/ | sed -n '1,40p'

# Kurztest: manueller Render-POST (funktioniert bereits — aus Deinem Output)
curl -sS -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "# Hello"
# Erwartet: JSON mit html`

# alle node prozesse ausgeben
tasklist | findstr node
# und Beenden
Stop-Process -Name node -Force
# oder
taskkill /F /IM node.exe
```


* Server-Health prüfen (lokal):
  `curl -sS http://localhost:43219/health`
  Rückgabe `ok` bedeutet: HTTP-Server läuft. (Port ggf. aus `require('mdview.config').defaults.server_port` oder `vim.g.mdview_server_port` anpassen.)

## client

```sh
# Prüfen, ob Vite dev läuft:
curl -sS http://localhost:43220/ | head -n 10

# Vite-dev-client prüfen (übliches dev-Setup verwendet Port 43220):
curl -sS http://localhost:43220/ | sed -n '1,40p'
```

- Vite läuft auf Port `43220`. `vite.config.ts` leitet `/ws` auf den Server `43219` weiter.
- `http://localhost:43219/` öffnen funktioniert nur, wenn der Node-Server korrekt läuft.
- Wenn Vite dev nicht läuft, bleibt `/ws` unverbunden → Browser zeigt „loading…“.

---

## Neovim

* In Neovim: `:MDViewShowLogs` (falls `config.debug = true`) um Runner-/Server-Logs zu sehen.
* `:checkhealth mdview` zeigt Runtime-Infos (Node/Bun, package.json-Status).

## Prozess auf dem Port 43219 beenden

```cmd
for /f "tokens=5" %a in ('netstat -ano ^| findstr :43219') do taskkill /F /PID %a
```

* `findstr :43219` sucht nur nach dem Port 43219.
* `tokens=5` greift auf die PID-Spalte von `netstat` zu.
* `taskkill /F /PID %a` beendet gezielt diesen Prozess.

In PowerShell geht es ähnlich:

```powershell
Get-Process -Id (Get-NetTCPConnection -LocalPort 43219).OwningProcess | Stop-Process -Force
```

## Alle `node.exe`-Prozesse beenden

**Eingabeaufforderung (CMD):**

```cmd
taskkill /F /IM node.exe
```

**PowerShell:**

```powershell
Stop-Process -Name node -Force
```

* `/F` bzw. `-Force` erzwingt das Beenden.
* Danach kannst du den Server erneut starten, ohne dass `EADDRINUSE` auftritt.

Hinweis: Dadurch werden **alle laufenden Node-Prozesse beendet**, also auch andere laufende Projekte/Server, die Node nutzen.

## `EADDRINUSE: address already in use :::43219`

Der Fehler `EADDRINUSE: address already in use :::43219` bedeutet, dass Node versucht, den Port 43219 zu binden, dieser aber bereits von einem anderen Prozess verwendet wird. Auch wenn `netstat` scheinbar nichts findet, kann es ein paar typische Ursachen geben:

1. **IPv6 vs. IPv4**

   * `::` ist die IPv6-Adresse `any`. Manche Tools wie `netstat` zeigen IPv4-Ports (`0.0.0.0`) standardmäßig an. Der Port kann durch einen IPv6-Listener blockiert sein.
   * Prüfen mit:

     ```powershell
     netstat -ano -p tcp | findstr 43219
     ```

     oder unter PowerShell:

     ```powershell
     Get-NetTCPConnection -LocalPort 43219
     ```

2. **Zombie-Node-Prozess**

   * Ein vorheriger `npm run dev:server` Prozess läuft noch im Hintergrund.
   * Prüfen mit:

     ```powershell
     tasklist | findstr node
     ```
   * Eventuell alte Prozesse killen:

     ```powershell
     taskkill /F /PID <pid>
     ```

---

# Commands

## Generell

- Im Terminal `curl -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "$(cat tests/test.md)"` ausführen — sollte JSON mit `html` zurückgeben.


## server

- Ports:

```sh
# powershell
netstat -ano | findstr 43219
taskkill /PID <PID> /F
Get-NetTCPConnection -LocalPort 43219 -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -ne 0 } | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }

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

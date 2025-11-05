# Commands

## Generell

- Im Terminal `curl -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "$(cat tests/test.md)"` ausführen — sollte JSON mit `html` zurückgeben.


## server

- Ports:

```sh
# powershell
netstat -ano | findstr 43219
taskkill /PID <PID> /F

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
```



* Server-Health prüfen (lokal):
  `curl -sS http://localhost:43219/health`
  Rückgabe `ok` bedeutet: HTTP-Server läuft. (Port ggf. aus `require('mdview.config').defaults.server_port` oder `vim.g.mdview_server_port` anpassen.)
* Manueller Render-Test (schnell):
  `curl -sS -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "# Hello\n\nThis is a test"`
  Antwort JSON mit `html` zeigt, dass Server Render und Broadcast schafft.

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

--

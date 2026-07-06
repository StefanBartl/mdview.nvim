# Checkpoint 1

## Table of content

  - [Prüfliste + gezielte Aktionen (Deutsch).](#prfliste-gezielte-aktionen-deutsch)
  - [Verhalten, das man möchte](#verhalten-das-man-mchte)
  - [Test-Anleitung, Schritt für Schritt](#test-anleitung-schritt-fr-schritt)
  - [Hinweise / Randfälle](#hinweise-randflle)
    - [Verhalten, das man möchte](#verhalten-das-man-mchte-1)
    - [Test-Anleitung, Schritt für Schritt](#test-anleitung-schritt-fr-schritt-1)
    - [Hinweise / Randfälle](#hinweise-randflle-1)
    - [Verhalten, das man möchte](#verhalten-das-man-mchte-2)
    - [Test-Anleitung, Schritt für Schritt](#test-anleitung-schritt-fr-schritt-2)
    - [Hinweise / Randfälle](#hinweise-randflle-2)

---

## Prüfliste + gezielte Aktionen (Deutsch).

1. Schnell prüfen, ob Server + Client erreichbar sind

* Server-Health:

```
curl -sS http://localhost:43219/health
# Erwartet: ok
```

* Server-Index prüfen (liefert HTML / client bootstrap):

```
curl -sS http://localhost:43219/ | sed -n '1,40p'
```

* Vite-dev-client prüfen (übliches dev-Setup verwendet Port 43220):

```
curl -sS http://localhost:43220/ | sed -n '1,40p'
```

Wenn `http://localhost:43219/` nur „mdview loading…“ zeigt, bedeutet das: der HTML-Client wurde geladen, aber der Browser-Client hat keine WS-Verbindung oder wartet auf Inhalte (oder der dev-client muss auf Port 43220 geöffnet werden).

1. Warum sieht man „mdview loading…“ im Browser?
2. Die Client-HTML zeigt initial nur einen Platzhalter (`<div id="mdview-root">mdview loading…</div>`).
3. Der Browser lädt anschließend das JS (Vite dev oder gebündelte `dist`) und eröffnet eine WebSocket-Verbindung zu `/ws`. Erst wenn der Client verbunden ist, empfängt er `render_update`-Nachrichten und zeigt gerendertes HTML.
4. Wenn kein Browser-Tab geöffnet ist oder der Browser nicht verbunden ist, sieht man weiter nur „loading…“.

3. Kurztest: manueller Render-POST (funktioniert bereits — aus Deinem Output)

```
curl -sS -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "# Hello"
# Erwartet: JSON mit html
```

Wenn das JSON kommt, rendert der Server korrekt. Fehlt im Browser die Darstellung, liegt es an Client/WS-Verbindung oder an falscher URL im Browser.

4. Browser automatisch öffnen: zwei Strategien
* Simple: immer `http://localhost:<server_port>` öffnen (bereits implementiert, aber im Dev-Setup evtl. nicht ideal).
* Besser fürs Dev-Setup: bevorzugt die Client-URL öffnen (Vite dev server), falls erreichbar (typisch 43220). Fallback auf Server-URL, falls kein dev-client läuft.

5. Schnelle Befehle in Neovim, um Browser manuell zu öffnen

* macOS:

```
:lua vim.fn.jobstart({"open", "http://localhost:43219"})
```

* Linux:

```
:lua vim.fn.jobstart({"xdg-open", "http://localhost:43219"})
```

* Windows (cmd):

```
:lua vim.fn.jobstart({"cmd", "/c", "start", "", "http://localhost:43219"})
```

6. Kleiner, sicherer Benutzerbefehl: füge `MDViewOpen` hinzu (nur das kleine Snippet, in english comments, EmmyLua not required here):

```lua
-- add to lua/mdview/usercommands.lua or plugin file
vim.api.nvim_create_user_command("MDViewOpen", function()
  local port = require("mdview.config").defaults.server_port or vim.g.mdview_server_port or 43219
  local server_url = "http://localhost:" .. tostring(port)
  -- prefer vite dev client if reachable
  local dev_port = 43220
  local function try_open(url)
    if vim.fn.has("win32") == 1 then
      vim.fn.jobstart({ "cmd", "/c", "start", "", url })
    elseif vim.fn.has("mac") == 1 then
      vim.fn.jobstart({ "open", url })
    else
      vim.fn.jobstart({ "xdg-open", url })
    end
  end
  -- quick probe of dev client
  local ok = (vim.fn.systemlist("curl -sS -I http://localhost:43220/ | head -n 1 2>/dev/null") ~= "")
  if ok then
    try_open("http://localhost:43220/")
  else
    try_open(server_url)
  end
end, { desc = "[mdview] Open preview in browser (tries vite dev then server)" })
```

7. Automatische Open-on-start: bessere Variante (füge in `lua/mdview/init.lua` in `M.start()` das folgende kleine Stück ein, es prüft zuerst Vite dev port 43220, dann server 43219):

```lua
-- after session.init() and events.attach()
local function probe_and_open(urls)
  for _, u in ipairs(urls) do
    -- quick non-blocking probe using curl; returns exit code 0 on success
    local cmd = { "sh", "-c", "curl -sS -I " .. u .. " >/dev/null 2>&1 && echo ok || echo no" }
    local ok = pcall(vim.fn.system, table.concat(cmd, " "))
    -- fallback simple: just attempt open if curl not available
    if ok then
      local res = vim.fn.system(table.concat(cmd, " "))
      if res:match("ok") then
        -- open and stop
        if vim.fn.has("win32") == 1 then
          vim.fn.jobstart({ "cmd", "/c", "start", "", u })
        elseif vim.fn.has("mac") == 1 then
          vim.fn.jobstart({ "open", u })
        else
          vim.fn.jobstart({ "xdg-open", u })
        end
        return true
      end
    end
  end
  -- fallthrough: try opening first URL anyway
  if vim.fn.has("win32") == 1 then
    vim.fn.jobstart({ "cmd", "/c", "start", "", urls[1] })
  elseif vim.fn.has("mac") == 1 then
    vim.fn.jobstart({ "open", urls[1] })
  else
    vim.fn.jobstart({ "xdg-open", urls[1] })
  end
  return true
end

-- example call: prefer vite then server
local server_port = M.config.server_port or vim.g.mdview_server_port or 43219
local server_url = string.format("http://localhost:%d", server_port)
local vite_url = "http://localhost:43220/"
vim.defer_fn(function() probe_and_open({ vite_url, server_url }) end, 1000)
```

Hinweis: `sh -c` probe ist plattformabhängig; für Windows muss man alternative Behandlung (PowerShell or cmd test) einbauen. Wenn Port-Probe zu kompliziert ist, einfach `open(server_url)` ohne Probe ist OK.

8. Warum Browser evtl. nicht automatisch kam bei Dir

* Logs zeigen `EADDRINUSE` dann nodemon restart — während des ersten Startversuchs war Port belegt, nodemon restartete; vielleicht wurde `wait_ready()` ausgeführt bevor nodemon final neu gestartet hat. `wait_ready()` pollt /health; ggf. Timeout überbrücken. Lösung: `wait_ready()` Timeout erhöhen (z. B. 10s) oder erst nach erfolgreichem "server running" Log öffnen.
* Dev-client (Vite) könnte nicht laufen — öffnet man server URL, client JS evtl. verweist auf vite dev URL, so Client nicht funktioniert. Deshalb Prefer-Vite-URL-Probe sinnvoll.

9. Wie bestätigen, dass Browser-Client live Updates sieht

* Öffne Browser manuell auf der gewählten URL (siehe oben).
* In Neovim: ändere Markdown, speichere (`:w`). Beobachte Browser; wenn WS-Verbindung aktiv, sollte Inhalt automatisch updaten.
* In Logs: `mdview` server log zeigt Broadcasts oder in mdview client console (Browser DevTools -> Console) sieht man WS open / messages.

10. Wenn nichts hilft — Debug-Hilfe:

* Schalte debug=true in `lua/mdview/config.lua` und `:MDViewShowLogs` öffnen.
* Setze `vim.g.mdview_server_port` falls custom port.
* Prüfe ob Vite dev server läuft: suche Prozess `vite` oder test `curl http://localhost:43220/`.

Zusammenfassung (konkret, was jetzt tun):
* `curl http://localhost:43219/health` -> ok (ist so)
* `curl http://localhost:43219/` -> prüfe HTML (zeigt client bootstrap)
* Falls vite dev vorhanden, öffne `http://localhost:43220/` statt server-url.
* Einen schnellen `:MDViewOpen`-Befehl anlegen (Code oben) — so kann man manuell ein Tab öffnen.
* Wenn automatische Open-on-start gewünscht: patch `M.start()` wie oben, erhöhe `wait_ready` timeout falls nodemon restart problematisch ist.

## Verhalten, das man möchte

1. `:MDViewStart` startet still den Server.
2. Sobald Server bereit ist, öffnet sich ein Browser-Tab (einmalig) auf der Server-URL.
3. Der aktuell geöffnete Markdown-Buffer wird einmalig an den Server gesendet (initial render), danach bei jedem `BufWritePost` erneut.

Die notwendigen Änderungen sind minimal:
* eine kleine, plattformübergreifende `open_browser(url)`-Routine hinzufügen, die `start()` einmal aufruft, wenn Server ready ist;
* sicherstellen, dass `send_current_buffer()` nach `wait_ready()` ausgeführt wird (das ist bereits integriert).

---

## Test-Anleitung, Schritt für Schritt

1. In Neovim in einem Markdown-Buffer `:edit tests/test.md` öffnen.
2. `:MDViewStart` ausführen.
   * Erwartung: `mdview: started` in :messages.
   * Browser sollte (innerhalb von ein paar Sekunden) ein Tab mit `http://localhost:43219` öffnen.
3. Falls kein Browser erscheint:
   * Prüfen, ob `curl http://localhost:43219/health` `ok` zurückgibt. Wenn nicht, schauen: `:MDViewShowLogs` (oder `:messages`) für Fehler.
   * Manuell im Terminal `curl -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "$(cat tests/test.md)"` ausführen — sollte JSON mit `html` zurückgeben.
4. In Neovim: `:w` (save) im Markdown-Buffer → Server sollte per `POST /render` die aktualisierte HTML an Clients broadcasten; Browser-Client (falls verbunden) zeigt Update.

---

## Hinweise / Randfälle

* Dev-Workflow: Wenn der client-dev (Vite) separat läuft, könnte man statt `http://localhost:43219` die dev-client-URL (`http://localhost:43220`) öffnen — das ist optional und hängt von Setup ab. Für Prod/distribution ist `http://localhost:<server_port>` korrekt. Wenn man Vite benutzt, lässt sich das Verhalten über `mdview.config` konfigurieren (z. B. `open_url`).
* Wenn `start` in einem Headless-Server (z. B. WSL ohne GUI) ausgeführt wird, schlägt `open_browser` still fehl; man kann `vim.env.MDVIEW_OPEN_CMD` setzen (z. B. `"/mnt/c/Windows/System32/cmd.exe /c start"`), oder `debug = true` nutzen und Logs prüfen.
* `ws_client.wait_ready()` benutzt `/health`-Polling; das sorgt dafür, dass initialer POST erst passiert, wenn HTTP-Server reagiert — dennoch enqueued `send_markdown()` Nachrichten und retryt, falls nötig.

---




### Verhalten, das man möchte

1. `:MDViewStart` startet still den Server.
2. Sobald Server bereit ist, öffnet sich ein Browser-Tab (einmalig) auf der Server-URL.
3. Der aktuell geöffnete Markdown-Buffer wird einmalig an den Server gesendet (initial render), danach bei jedem `BufWritePost` erneut.

Die notwendigen Änderungen sind minimal:
* eine kleine, plattformübergreifende `open_browser(url)`-Routine hinzufügen, die `start()` einmal aufruft, wenn Server ready ist;
* sicherstellen, dass `send_current_buffer()` nach `wait_ready()` ausgeführt wird (das ist bereits integriert).

---

### Test-Anleitung, Schritt für Schritt

1. In Neovim in einem Markdown-Buffer `:edit tests/test.md` öffnen.
2. `:MDViewStart` ausführen.
   * Erwartung: `mdview: started` in :messages.
   * Browser sollte (innerhalb von ein paar Sekunden) ein Tab mit `http://localhost:43219` öffnen.
3. Falls kein Browser erscheint:
   * Prüfen, ob `curl http://localhost:43219/health` `ok` zurückgibt. Wenn nicht, schauen: `:MDViewShowLogs` (oder `:messages`) für Fehler.
   * Manuell im Terminal `curl -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "$(cat tests/test.md)"` ausführen — sollte JSON mit `html` zurückgeben.
4. In Neovim: `:w` (save) im Markdown-Buffer → Server sollte per `POST /render` die aktualisierte HTML an Clients broadcasten; Browser-Client (falls verbunden) zeigt Update.

---

### Hinweise / Randfälle

* Dev-Workflow: Wenn der client-dev (Vite) separat läuft, könnte man statt `http://localhost:43219` die dev-client-URL (`http://localhost:43220`) öffnen — das ist optional und hängt von Setup ab. Für Prod/distribution ist `http://localhost:<server_port>` korrekt. Wenn man Vite benutzt, lässt sich das Verhalten über `mdview.config` konfigurieren (z. B. `open_url`).
* Wenn `start` in einem Headless-Server (z. B. WSL ohne GUI) ausgeführt wird, schlägt `open_browser` still fehl; man kann `vim.env.MDVIEW_OPEN_CMD` setzen (z. B. `"/mnt/c/Windows/System32/cmd.exe /c start"`), oder `debug = true` nutzen und Logs prüfen.
* `ws_client.wait_ready()` benutzt `/health`-Polling; das sorgt dafür, dass initialer POST erst passiert, wenn HTTP-Server reagiert — dennoch enqueued `send_markdown()` Nachrichten und retryt, falls nötig.

---


### Verhalten, das man möchte

1. `:MDViewStart` startet still den Server.
2. Sobald Server bereit ist, öffnet sich ein Browser-Tab (einmalig) auf der Server-URL.
3. Der aktuell geöffnete Markdown-Buffer wird einmalig an den Server gesendet (initial render), danach bei jedem `BufWritePost` erneut.

Die notwendigen Änderungen sind minimal:
* eine kleine, plattformübergreifende `open_browser(url)`-Routine hinzufügen, die `start()` einmal aufruft, wenn Server ready ist;
* sicherstellen, dass `send_current_buffer()` nach `wait_ready()` ausgeführt wird (das ist bereits integriert).

---

### Test-Anleitung, Schritt für Schritt

1. In Neovim in einem Markdown-Buffer `:edit tests/test.md` öffnen.
2. `:MDViewStart` ausführen.
   * Erwartung: `mdview: started` in :messages.
   * Browser sollte (innerhalb von ein paar Sekunden) ein Tab mit `http://localhost:43219` öffnen.
3. Falls kein Browser erscheint:
   * Prüfen, ob `curl http://localhost:43219/health` `ok` zurückgibt. Wenn nicht, schauen: `:MDViewShowLogs` (oder `:messages`) für Fehler.
   * Manuell im Terminal `curl -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "$(cat tests/test.md)"` ausführen — sollte JSON mit `html` zurückgeben.
4. In Neovim: `:w` (save) im Markdown-Buffer → Server sollte per `POST /render` die aktualisierte HTML an Clients broadcasten; Browser-Client (falls verbunden) zeigt Update.

---

### Hinweise / Randfälle

* Dev-Workflow: Wenn der client-dev (Vite) separat läuft, könnte man statt `http://localhost:43219` die dev-client-URL (`http://localhost:43220`) öffnen — das ist optional und hängt von Setup ab. Für Prod/distribution ist `http://localhost:<server_port>` korrekt. Wenn man Vite benutzt, lässt sich das Verhalten über `mdview.config` konfigurieren (z. B. `open_url`).
* Wenn `start` in einem Headless-Server (z. B. WSL ohne GUI) ausgeführt wird, schlägt `open_browser` still fehl; man kann `vim.env.MDVIEW_OPEN_CMD` setzen (z. B. `"/mnt/c/Windows/System32/cmd.exe /c start"`), oder `debug = true` nutzen und Logs prüfen.
* `ws_client.wait_ready()` benutzt `/health`-Polling; das sorgt dafür, dass initialer POST erst passiert, wenn HTTP-Server reagiert — dennoch enqueued `send_markdown()` Nachrichten und retryt, falls nötig.

---


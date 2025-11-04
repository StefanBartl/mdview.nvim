# Nächste Schritte & aktualisierte Roadmap für mdview.nvim

## Kurze Bestandsaufnahme (aktueller Stand)

* [x] `npm run dev` / `npm run build` laufen ohne Fehler.
* [x] Vite-Client erreichbar unter `http://localhost:43220/` — zeigt "mdview loading...".
* [ ] `lua/`-Ordner noch nicht vorhanden (Neovim-Plugin fehlt aktuell).
* [ ] Server liefert aktuell nur eine einfache WS-Verbindung / Hello-Message; Render-Endpoint fehlt noch.

---

## Ziel für die nächste Iteration (Sprintziel)

1. Minimaler End-to-End-Test mit einer echten Markdown-Datei: Neovim (später) → Server (render) → Browser (Anzeige).
2. Minimales Lua-Scaffold anlegen, damit Neovim später kontrolliert den Server starten/stoppen.
3. Transport-Abstraktion (clientseitig) finalisieren: Factory + WebSocket impl. WebTransport stub bereits als POC-Datei vorgesehen, Dev-opt-in Flag eingefügt.

---

## Konkrete, priorisierte Aufgaben (mit Checkboxen)

### A — Schneller E2E-Smoke mit Markdown (server+client)

* [ ] `src/server/render.ts` implementieren: HTTP POST `/render` oder GET `/render?path=...` → Markdown → HTML (markdown-it).
* [ ] Server: `/render` Endpoint in `src/server/index.ts` anfügen (falls dev: POST raw markdown body).
* [ ] Client: optional Button/Dev-UI oder manual curl/post testen: `curl -XPOST http://localhost:43219/render -d @test.md -H "Content-Type:text/markdown"` → HTTP antwortet HTML.
* [ ] Client: ergänzen, damit bei manueller Test-POST das Resultat in `#mdview-root` angezeigt wird (z. B. dev route `/preview?src=http://...` oder via WS broadcast).
* [ ] Testdatei anlegen: `tests/test.md` mit typischen Inhalten (Headings, links, images, anchors).
* [ ] Smoke: POST `tests/test.md` → Browser zeigt gerendertes HTML.

### B — Minimaler Neovim-Adapter (Scaffold)

* [ ] `plugin/mdview.lua` erstellen (ein einfacher `:MarkdownPreviewStart` Command, der `lua require('mdview').start()` aufruft).
* [ ] `lua/mdview/init.lua` minimal: `setup()` + Export `start()`/`stop()` (Dev-API).
* [ ] `lua/mdview/adapter/runner.lua` implementieren: `start_server(runtimeCmd, entry)` utilisant `vim.loop.spawn` (Speichert PID/Handle).
* [ ] `lua/mdview/adapter/ws_client.lua` minimal: falls gewünscht direkte WS-Client-Kommunikation in Lua (optional; zunächst reicht server spawn).
* [ ] Manueller Test in Neovim: `:source plugin/mdview.lua` → `:MarkdownPreviewStart` startet server process (prüfen via `ps`/tasklist).

### C — Client Transport Abstraktion & Integration

* [x] `src/client/dev-config.ts` (DEV_USE_WEBTRANSPORT flag) angelegt.
* [ ] `src/client/transport/transport.interface.ts` anlegen (falls noch nicht).
* [ ] `src/client/transport/websocket.transport.ts` finalisieren und testen.
* [ ] `src/client/transportFactory.ts` in `main.ts` verwenden (bereits eingebunden) — Unit-Tests für Factory schreiben (mocks).
* [ ] `src/client/transport/webtransport.transport.ts` bleibt POC/stub; Integration erst später (opt-in).

### D — Tests & CI Ergänzungen

* [ ] Unit-Test: `src/server/render.test.ts` (vitest) für Markdown→HTML.
* [ ] Integration E2E-Smoke: Script `scripts/e2e-smoke.sh` (start server, curl POST, check HTML contains known marker).
* [ ] CI: job ergänzt, der `npm run build` + `npm run test` ausführt (falls noch nicht vorhanden).

### E — Performance / Hygiene (kurz)

* [ ] Debounce/Coalesce in Server: einfache 50–200ms debounce für aufeinanderfolgende Render-Requests implementieren.
* [ ] Cache: einfache Datei-hash-Prüfung bevor komplettes Render gestartet wird (schnelle Win).
* [ ] Logging: server log level / debug flag einführen.

---

## Was kann jetzt schon abgearbeitet werden (quick wins)

* [ ] Implementiere `/render` Endpoint (server) — sehr kleiner Aufwand, großer Nutzen: ermöglicht sofortiges Testing mit `curl`.
* [ ] Erzeuge `tests/test.md` und verifiziere über `curl` → Browser; damit ist Proof-of-Concept minimal erledigt.
* [ ] Lege `plugin/mdview.lua` + `lua/mdview/init.lua` als minimalen Stub an, sodass `:MarkdownPreviewStart` in Neovim den vorhandenen `npm run dev:server` Prozess starten/stoppen kann (spawn command).
* [ ] Ergänze README mit Dev-Schritt "How to test local render endpoint".

---

## Konkrete Befehle / Snippets (für die unmittelbare Arbeit)

### 1) Test-Markdown erstellen

Datei `tests/test.md`:

```markdown
# Test Document

This is a simple test for mdview.

## Anchor section

Some text with [a link to anchor](#anchor-section).

## Another file link
[Other file](../README.md)

### anchor-section
This is the anchor target.
```

### 2) Beispiel-curl um `/render` zu testen (nach Implementierung)

```bash
curl -X POST "http://localhost:43219/render" \
  -H "Content-Type: text/markdown" \
  --data-binary "@tests/test.md"
```

Erwartung: HTML als Response (prüfbar mit `grep '<h1'` oder Browser anzeigen).

### 3) Neovim: minimaler Start-Command (als Übergangslösung)

In `lua/mdview/adapter/runner.lua` minimal:

```lua
local uv = vim.loop

local function start_server()
  local handle, pid = uv.spawn("npm", {
    args = {"run", "dev:server"},
    stdio = {nil, vim.loop.new_pipe(false), vim.loop.new_pipe(false)},
  }, function(code, signal)
    print("server exited", code, signal)
  end)
  return { handle = handle, pid = pid }
end
```

Im `plugin/mdview.lua`:

```lua
vim.api.nvim_create_user_command("MarkdownPreviewStart", function()
  require("mdview").start()
end, {})
```

---

## Was ist neu in der Roadmap / was wurde ergänzt

* Transport-Factory & WebTransport POC als Dev-opt-in sind hinzugefügt und müssen in Phase C getestet.
* Explizite Aufgabe: `/render` Endpoint (Phase B) wurde priorisiert, weil er schnellen E2E-Test ermöglicht.
* Minimales Lua-Scaffold (Phase A) wurde als „quick win“ priorisiert, damit Neovim-Integration schnellstmöglich real getestet werden kann.
* Testaufgaben konkretisiert: `curl` smoke, vitest unit test für renderer, E2E smoke script.

---

## Vorschlag für die nächsten 48 Stunden (Sprint-Plan)

* Tag 1:

  * Implementiere `src/server/render.ts` und Endpoint in `index.ts`.
  * Lege `tests/test.md` an und teste mit `curl`.
  * Ergänze README Dev-Anleitung mit curl-Beispiel.
* Tag 2:

  * Minimaler Lua-Scaffold (`plugin/mdview.lua`, `lua/mdview/init.lua`, runner.lua).
  * Test: Starte server per `:MarkdownPreviewStart` in Neovim (headless oder GUI) — prüfe Process gestartet.
  * Implementiere einfache debounce + file-hash precheck im Server.
  * Schreibe minimalen vitest Unit-Test für Renderfunktion.

---

## Risiken & Abhängigkeiten

* Neovim-Integration auf Windows: spawn/Signals können unterschiedlich arbeiten; testen auf Zielplattform notwendig.
* WebTransport-POC bleibt experimentell — kein Produktivdruck darauf.
* TLS/HTTP-3 / Bun als Option sind später zu adressieren (Roadmap).

---


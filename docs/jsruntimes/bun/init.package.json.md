# Bun-Implementierung — Leitfaden für späteres Feature (Dokumentation)

## Ziel

Beschreiben, wie man den Server-Teil von mdview.nvim alternativ in **Bun** implementiert, welche Anpassungen nötig sind, welche Vorteile/Nachteile bestehen und welche konkreten Dateien / Scripts man anlegt. Die Anleitung ist so gehalten, dass sie direkt in die Dokumentation/README übernommen werden kann.

---

# Kurzüberblick — Entscheidungskriterien

* Default bleibt **Node.js** (niedrigste Eintrittsbarriere).
* Bun wird als **optionale** Runtime angeboten (Roadmap-Meilenstein M3).
* Bun eignet sich für Entwicklungs- & Performance-optimierungen (schneller Start, integrierte HTTP/WebSocket, native TypeScript).
* Implementationsstrategie: **Feature-Flagged** Server-Start (Lua → spawn entweder `node` oder `bun`), Bibliotheken so wählen, dass sie unter beiden Runtimes funktionieren oder Bun-spezifische Pfade haben.

---

# Architektur-Änderungen / Unterschiede gegenüber Node.js

* Bun erlaubt das direkte Ausführen von TypeScript-Dateien ohne Transpile-Step (`bun src/server/index.ts`).
* Native APIs: `Bun.serve` (HTTP), WebSocket-Upgrade via `new WebSocket()` oder `req.upgrade()` Patterns sind verfügbar. Bei komplexer WS-Logik kann man trotzdem die standardisierte `ws`-API nachbauen.
* Filewatching: Bun bietet oft eingebaute Hot-Reload/Watch-Optionen; alternativ `chokidar` funktioniert unter Bun, aber man sollte Bun-native Features prüfen.
* Paketmanagement: Bun verwendet `bun.lockb`. Wenn Bun optional ist, sollte man `bun.lockb` ggf. ignorieren oder optional im Repo haben.
* WASM: WebAssembly APIs in Bun entsprechen Web-Standards; serverseitiges Laden und Instantiating von `.wasm` funktioniert ähnlich wie in Node/Browser.

---

# Dateien & Scripts (Vorschlag)

Empfohlene Ergänzungen / Alternativen für vorhandene Struktur:

* `src/server/bun.server.ts` — Bun-spezifische Server-Implementierung (minimal, performant).
* `package.json` — neue Scripts:

  * `"start:node": "node ./dist/server/index.js"`
  * `"dev:node": "ts-node-dev --respawn --transpile-only src/server/index.ts"`
  * `"start:bun": "bun src/server/bun.server.ts"`
  * `"dev:bun": "bun --watch src/server/bun.server.ts"` *(oder `bun src/server/bun.server.ts --watch` je nach Bun-Version)*
* Optional: `bunfig.toml` (falls man Bun spezifische Konfiguration verwenden möchte).
* `.gitignore`: `bun.lockb` ggf. aufnehmen oder dokumentieren, dass es optional ist.

---

# Beispiel: minimaler Bun Server (TypeScript)

Die folgende Datei zeigt ein kleines, bewährtes POC-Pattern: HTTP für statische Assets + WebSocket-Broadcast für Render-Updates. Code-Kommentare sind in Englisch (Code muss immer englische Kommentare haben).

Datei: `src/server/bun.server.ts`

```ts
// Minimal Bun server for mdview.nvim POC
// - Serves static client assets
// - Maintains WebSocket connections for live updates
// - Exposes a simple HTTP "render" endpoint (GET/POST) for tests

import { serve } from "bun"; // Bun global API

const PORT = Number(process.env.MDVIEW_PORT || 43219);
const STATIC_ROOT = new URL("../../dist/client", import.meta.url).pathname;

/**
 * Simple in-memory client registry for broadcasting render updates
 * Keys are incremental connection ids; values are WebSocket objects
 */
const clients = new Map<number, WebSocket>();
let nextId = 1;

/**
 * Utility: send object as JSON over a WebSocket connection
 */
function wsSend(ws: WebSocket, type: string, payload: unknown) {
  try {
    ws.send(JSON.stringify({ type, payload }));
  } catch (e) {
    // ignore send errors, will be cleaned up on close
  }
}

/**
 * Serve handler: routes:
 * - "/" -> index.html from client dist
 * - "/ws" -> WebSocket upgrade / connection handling
 * - "/render" -> simple POST/GET to trigger broadcast (for testing)
 */
serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);

    // WebSocket upgrade path
    if (url.pathname === "/ws") {
      // Bun supports request.upgrade for WebSocket upgrades
      const { 0: ws, 1: res } = Bun.upgradeWebSocket(req, {
        // Optional WebSocket lifecycle callbacks
        open(ws) {
          const id = nextId++;
          // store ws on open
          clients.set(id, ws);
          (ws as any).__mdview_id = id;
          console.log(`[bun] ws open id=${id}, clients=${clients.size}`);
        },
        message(ws, message) {
          // incoming messages from client (if needed)
          // no-op for POC
          // console.log("ws msg", message.toString());
        },
        close(ws) {
          const id = (ws as any).__mdview_id;
          if (id) {
            clients.delete(id);
            console.log(`[bun] ws close id=${id}, clients=${clients.size}`);
          }
        },
        error(ws, err) {
          console.warn("[bun] ws error", err);
        },
      });

      return res;
    }

    // Render API (simple): accepts POST with html payload to broadcast to clients
    if (url.pathname === "/render" && req.method === "POST") {
      try {
        const body = await req.text();
        // Broadcast render update to all connected clients
        for (const ws of clients.values()) {
          wsSend(ws, "render_update", body);
        }
        return new Response("OK", { status: 200 });
      } catch (err) {
        return new Response(String(err), { status: 500 });
      }
    }

    // Serve static files: index.html and assets under dist/client
    // Try to resolve a file under STATIC_ROOT; fallback to index.html
    try {
      const fileUrl = new URL(url.pathname, `file://${STATIC_ROOT}`);
      // Bun.serve can return a file response if file exists; use Bun.file
      try {
        return new Response(Bun.file(fileUrl.pathname));
      } catch {
        // fallback to index.html
        return new Response(Bun.file(new URL("index.html", `file://${STATIC_ROOT}`).pathname));
      }
    } catch (err) {
      return new Response("Not found", { status: 404 });
    }
  },
});

console.log(`[bun] mdview server listening at http://localhost:${PORT}`);
```

Hinweise zum Code:

* `Bun.upgradeWebSocket` ist das empfohlene Pattern zum Upgrade (API-Surface kann je nach Bun-Version variieren).
* Der Server nutzt `Bun.file` zum Liefern statischer Assets (schnell & zero-copy).
* Broadcast muss robust gegenüber disconnects sein — in POC reicht Map + cleanup auf `close`.
* Für produktive Nutzung sollte man MessagePack/CBOR erwägen und Heartbeat/Backpressure implementieren.

---

# Beispiel: Anpassung Neovim-Adapter (Lua) zum Starten von Bun

`lua/mdview/adapter/runner.lua` — minimaler Spawn-Wrapper (Lua)

```lua
-- spawn a persistent server process (either node or bun) using vim.loop.spawn
-- English comments in code as required.

local uv = vim.loop
local M = {}

--- Start server with given runtime choice
---@param runtime string "node" | "bun"
---@param entry string path to server entry (absolute or relative)
---@return table handle process handle
function M.start_server(runtime, entry)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  local args = {}
  if runtime == "node" then
    args = { entry }
  elseif runtime == "bun" then
    -- Bun can execute TS directly; call bun with the entry file
    args = { entry } -- bun executable will be the cmd
  end

  local handle, pid
  handle, pid = uv.spawn(runtime, {
    args = args,
    stdio = {nil, stdout, stderr},
    env = vim.fn.environ(),
  }, function(code, signal)
    -- process exit callback
    stdout:close()
    stderr:close()
    handle:close()
    vim.schedule(function()
      vim.notify(string.format("mdview server exited (code=%s, signal=%s)", tostring(code), tostring(signal)))
    end)
  end)

  -- attach readers
  stdout:read_start(function(err, data)
    if err then
      vim.schedule(function() vim.notify("mdview stdout error: " .. tostring(err)) end)
      return
    end
    if data then
      vim.schedule(function() vim.notify("[mdview server] " .. data) end)
    end
  end)
  stderr:read_start(function(err, data)
    if err then
      vim.schedule(function() vim.notify("mdview stderr error: " .. tostring(err)) end)
      return
    end
    if data then
      vim.schedule(function() vim.notify("[mdview server err] " .. data) end)
    end
  end)

  return { handle = handle, pid = pid }
end

return M
```

Erläuterung:

* `runtime` Parameter steuert, ob `node` oder `bun` als Executable aufgerufen wird.
* Wenn `bun` gewählt ist, erwartet Bun die Ausführbarkeit von TypeScript direkt (kein tsc required).
* Der Plugin-Setup API (`require('mdview').setup`) sollte `server_runtime` Option unterstützen.

---

# WASM in Bun server nutzen

* Bun unterstützt WebAssembly über Standard-API (`WebAssembly.instantiate` / `WebAssembly.instantiateStreaming`).
* Serverseitig kann man `.wasm` via `await Bun.file('./wasm/module.wasm').arrayBuffer()` laden und instantiieren.
* Vorteil: man kann das gleiche WASM-Modul server/client verwenden (single source).
* Caveat: manche Wasm-Toolchains geben unterschiedliche imports; test & adapt.

Beispiel (pseudo):

```ts
// load wasm once at startup
const wasmBuf = await Bun.file(new URL('../../wasm/markdown.wasm', import.meta.url).pathname).arrayBuffer();
const wasmModule = await WebAssembly.instantiate(wasmBuf, /* imports */ {});
const wasmExport = wasmModule.instance.exports;
```

---

# Dev / CI Anpassungen für Bun

* `package.json` Scripts ergänzen (siehe oben).
* CI: Falls man Bun-Matrix testen möchte, CI Job für Bun hinzufügen (optional, später). Minimal: Node CI beibehalten.
* `.github/workflows/ci.yml` Ergänzungen (wenn Bun getestet werden soll):

  * Job oder Matrix-Entry `runs-on: ubuntu-latest` + `actions/setup-node` optional, aber zusätzlich `bun install` (install Bun in runner) — oder use prebuilt Bun action.
* Dokumentiere in README: wie man Bun installiert und wie man dev:scripts mit Bun startet.

---

# Migrations-/Kompatibilitätscheckliste (Checkboxes)

* [ ] API-Abstraktion: Adapter so schreiben, dass Node/Bun gleichermaßen verwendbar sind (single entry point but runtime switch).
* [ ] `package.json` Scripts: `start:node`, `start:bun`, `dev:node`, `dev:bun`.
* [ ] Document `server_runtime` option in `mdview.setup({ server_runtime = "node" | "bun" })`.
* [ ] CI: Entscheidung ob Bun in CI ausgeführt wird (add optional CI job).
* [ ] Lockfile policy: entscheiden ob `bun.lockb` commited wird (document rationale).
* [ ] Test Bun on target platforms (Linux/macOS; Windows Bun support may be limited).
* [ ] Ensure dependencies used are Bun-compatible (some native Node modules may not work).
* [ ] WASM loading tests: instantiate wasm in Bun, run a few sample inputs.
* [ ] Performance Benchmark: compare Node vs Bun cold start & steady state for same workload.
* [ ] Fallback: if Bun not found on PATH, plugin should fall back to Node or show clear error message with installation instructions.

---

# Empfehlungen / Best Practices

* Implementiere zuerst Node.js (default). Mache die Server-code so portable wie möglich (avoid heavy Node-only APIs).
* Pflege eine kleine, gut dokumentierte `bun.server.ts` die bun-native Vorteile nutzt (Bun.file, Bun.upgradeWebSocket, Bun.serve).
* Halte die Protocol-Spec (WS message types) runtime-agnostisch; dieselben messages sollen von Node und Bun bedient werden.
* Documentiere ausführlich: How-to-install-bun, welche bun-version empfohlen wird, known issues.
* Teste Bun-Implementierung auf einem CI-Runner lokal bevor man CI-Matrix ergänzt.

---

# Beispiel README-Abschnitt (für spätere Einbindung)

````markdown
## Optional: Run server with Bun

Bun offers a fast runtime with built-in TypeScript support and performant static file serving.

### Install Bun (macOS / Linux)
Follow official Bun installation docs for the target platform.

### Start dev server with Bun
```bash
# start Bun server (client dev server still via Vite)
bun src/server/bun.server.ts
````

### package.json scripts

* `npm run dev:bun` — starts dev server using Bun (if Bun installed)
* `npm run start:bun` — start built/production Bun server

Note: Node.js remains the default runtime. Bun support is optional and documented as a Roadmap feature (M3).

```

---

# Zusammenfassung (Kurz)
- Bun bringt Vorteile (start time, integrated TS, fast file serving).
- Implementationsstrategie: runtime-switch via config; Node bleibt Default.
- Datei- bzw. Script-Vorschläge, Bun POC-Server mit WebSocket und static serving, Lua-spawn Wrapper, CI-Hinweise und Checkliste wurden bereitgestellt.

---
::contentReference[oaicite:0]{index=0}
```

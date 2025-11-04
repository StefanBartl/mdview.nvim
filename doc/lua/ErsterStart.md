# Localer Eintrag für Lazy (Beispiel)

```lua
-- add to your plugins.personal file
-- English comments inside code as required by project rules

if not vim.env.REPOS_DIR then
  vim.notify("[PLUGINS PERSONAL] REPOS_DIR not set. mdview.nvim not available.", vim.log.levels.WARN)
  return {}
end

return {
  {
    -- local development: adjust path to your repo root
    dir = vim.fn.expand(vim.env.REPOS_DIR .. "/mdview.nvim"),
    name = "mdview.nvim",
    -- load eagerly for development so commands are available immediately
    lazy = false,
    -- do not automatically run setup; the plugin exposes :MarkdownViewStart / :MarkdownViewStop
    config = function()
      -- optional: expose server port if different than default
      vim.g.mdview_server_port = 43219

      -- minimal setup placeholder (future: require('mdview').setup({...}))
      if pcall(require, "mdview") then
        -- keep default config for now
      else
        vim.notify("mdview.nvim: module not found after loading plugin files", vim.log.levels.ERROR)
      end
    end,
    -- make the commands discoverable to lazy if desired
    cmd = { "MarkdownViewStart", "MarkdownViewStop" },
  },
}
```

# Voraussetzungen vor dem ersten Start (Checklist)

* Node.js / npm oder Bun installiert (Node empfohlen als Default).
* In Projekt-Repo: `package.json` + `node_modules` (z. B. `npm install`) — für lokalen Dev-Server.
* `curl` auf dem System verfügbar (ws_client.lua verwendet curl als HTTP-POST-Fallback). Auf Windows: Git for Windows liefert curl; sonst separat installieren.
* `plugin/mdview.lua` und `lua/mdview/*` Dateien müssen im Repo vorhanden sein (wie bereits erzeugt).

# Lokaler Workflow nach Installation in Lazy

1. Neovim starten (oder `:Lazy sync` / `:Lazy load` ausführen, falls Lazy konfiguriert).
2. Prüfen, ob Plugin-Dateien geladen wurden:

   * `:scriptnames` → Suche nach `plugin/mdview.lua` oder `lua/mdview/init.lua`.
3. Starten der Preview-Umgebung:

   * In Neovim ausführen: `:MarkdownViewStart`

     * Plugin startet lokal den dev-server (standard: `npm run dev:server`) via runner.spawn.
     * Plugin legt Autocommands an (`BufEnter`, `BufWritePost`).
4. Nach Start: Browser öffnen `http://localhost:43220/` (Vite client) oder `http://localhost:43219/health` (server health).
5. Datei speichern: bei `BufWritePost` sendet Plugin per HTTP-POST das Markdown an `http://localhost:43219/render?key=...`. Browser sollte per WebSocket `render_update` erhalten und anzeigen.

# Troubleshooting (häufige Fehler & Prüfungen)

* Plugin-Command nicht verfügbar:

  * Prüfen: `:Lazy status` oder `:scriptnames` ob `plugin/mdview.lua` geladen ist.
  * Falls nicht geladen: `:luafile /voller/pfad/zum/repo/plugin/mdview.lua` zum schnellen Test.
* `:MarkdownViewStart` führt nicht aus / Fehler:

  * `:messages` prüfen auf Fehlermeldungen (spawn-Fehler, fehlende npm).
  * In Terminal prüfen, ob Prozess gestartet wurde (`ps` / `tasklist` bzw. `:echo v:servername` nicht relevant).
* Server-Start schlägt fehl:

  * Direkt im Repo-Root in einem Terminal `npm run dev:server` ausführen — Fehlermeldungen dort sind leichter zu debuggen.
  * Prüfen, ob `package-lock.json` / `node_modules` vorhanden sind (`npm install` falls nötig).
* HTTP-POST schlägt fehl (ws_client):

  * Prüfen, ob `curl` vorhanden (`:echo vim.fn.executable("curl")`).
  * Prüfen Server-Health: `curl http://localhost:43219/health` oder im Browser `http://localhost:43219/health`.
* WebSocket-Verbindung nicht aufgebaut:

  * Browser-Console (DevTools) prüfen; WebSocket-URL `ws://localhost:43219/ws` sollte verbunden sein.
  * Server-Log prüfen (in Neovim-Ausgabe oder in Terminal beim direct `npm run dev:server`).
* Windows-spezifika:

  * `runner` nutzt `vim.loop.spawn` — manchmal unterscheiden sich Signal-Handling und PATH. Bei Problemen `cmd` + `args` anpassen oder server manuell starten.
* LSP- und Diagnostic-Warnungen in Lua-Code:

  * Diese Diagnosen sind meist nur LSP-False-Positives wegen `vim.loop`/`luv`. Laufzeit ist normalerweise unaffected. Falls störend: adjust Sumneko / lua-language-server settings to include luv runtime typedefs.

# Nützliche Quick-Commands in Neovim (Debug)

* Plugin-Datei erneut laden:

```vim
:luafile $REPOS_DIR/mdview.nvim/plugin/mdview.lua
```

* Server manuell starten (falls runner scheitert):

```vim
:!cd /path/to/mdview.nvim && npm run dev:server &
```

* Server stoppen (Windows):

```vim
:lua require("mdview").stop()
```

oder extern:

```powershell
taskkill /F /IM node.exe
```

# Empfehlungen für lokalen Development Setup

* Während Entwicklung `lazy = false` setzen, damit Änderungen an `lua/` sofort beim Start sichtbar sind.
* Empfohlen: zwei Terminal-Tabs offen

  * Tab A: `npm run dev` (client+server) — schnelle iteration client-side
  * Tab B: `nvim` (mit plugin geladen) — Neovim-Seite testen
* Wenn `curl` auf Windows problematisch ist, setze in `ws_client.lua` temporär `http_post` auf eine PowerShell-`Invoke-RestMethod`-Variante oder starte Server manuell und teste mit `curl` extern.

# Optional: Alternative lokale `dir`-Angabe (kein REPOS_DIR)

```lua
-- use explicit absolute path if REPOS_DIR not desired
{
  dir = vim.fn.expand("~/code/mdview.nvim"), -- adjust to local path
  name = "mdview.nvim",
  lazy = false,
  cmd = { "MarkdownViewStart", "MarkdownViewStop" },
  config = function() vim.g.mdview_server_port = 43219 end,
}
```

# Kurze Checkliste vor dem ersten realen Test (abhakbar)

* [ ] `dir` in plugins.personal auf das lokale Repo gesetzt
* [ ] `npm install` im Repo ausgeführt (node_modules vorhanden)
* [ ] `curl` auf System verfügbar (oder server manuell startbar)
* [ ] `:MarkdownViewStart` startet ohne sofortige Fehlermeldung
* [ ] Browser zeigt `mdview loading...` und WebSocket verbindet sich (Browser-Console prüfen)
* [ ] `:write` einer Markdown-Datei löst POST an `/render` aus und Browser erhält `render_update`

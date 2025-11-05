# Roadmap mit Checkliste für Entwicklung, Tests und Integration von mdview.nvim

## Table of content

  - [Repository & Basissetup](#repository-basissetup)
  - [Phase A — Core Neovim Plugin (Minimal viable Lua core)](#phase-a-core-neovim-plugin-minimal-viable-lua-core)
  - [Phase B — Minimaler Server (Node.js default; Bun optional später)](#phase-b-minimaler-server-nodejs-default-bun-optional-spter)
  - [Phase C — Browser Client (TypeScript, WebWorker optional)](#phase-c-browser-client-typescript-webworker-optional)
  - [Phase D — Integration Neovim ↔ Server ↔ Browser](#phase-d-integration-neovim-server-browser)
  - [Phase E — Performance-Optimierungen & WASM POC](#phase-e-performance-optimierungen-wasm-poc)
  - [Phase F — Feature-Set Ergänzungen & Konfigurationsoptionen](#phase-f-feature-set-ergnzungen-konfigurationsoptionen)
  - [Phase G — CI, Packaging, Release](#phase-g-ci-packaging-release)
  - [Priorisierte Checkliste (Kurzversion, für Sprint-Board)](#priorisierte-checkliste-kurzversion-fr-sprint-board)
  - [Empfehlungen für Sprintplanung & Tests](#empfehlungen-fr-sprintplanung-tests)
  - [Zusätzliche Hinweise](#zustzliche-hinweise)

--

## Repository & Basissetup

* [x] Repository initialisieren (Git) und README / LICENSE anlegen
* [x] .gitignore ergänzen
* [x] Monorepo-/Ordnerstruktur anlegen:
  * [x] `lua/mdview/` (Neovim Lua Core)
  * [x] `plugin/` (plugin loader)
  * [x] `src/server/` (Node.js/Bun server)
  * [x] `src/client/` (TypeScript client)
  * [x] `wasm/` (WASM proof-of-concept / bindings)
  * [x] `tests/` (Unit & Integration tests)
  * [x] `ci/` (CI Konfiguration)
* [ ] Initiale Dev-Skripte in `package.json` (dev, build, test, lint)
    * [x] CI (GitHub Actions) anlegen: `.github/workflows/ci.yml`
    * [x] `./package.json` für NodeJS anlegen
    * [x] `./tsconfig.json` anlegen
    * [x] `./src/client/vite.config.ts` anlegen
    * [x] `./.eslintrc.cjs` anlegen
    * [x] `./.prettierrc` anlegen
    * [x] `./src/server/index.ts` Minimalen Server-Entrypoint (TypeScript) anlegen
    * [x] `./src/client/index.ts` Minimalen Client-Entrypoint (TypeScript) anlegen
    * [x] DevDependencies installieren (`npm ci` nach package.json)
    * [x] Erster Dev-Start testen: `npm run dev`

-

## Phase A — Core Neovim Plugin (Minimal viable Lua core)

Ziel: Neovim erkennt Markdown-Buffer und startet/stellt Verbindung zum lokalen Server her.

* [x] `plugin/mdview.lua` anlegen (autoload entry, commands)
* [x] `lua/mdview/init.lua` (Modul-Entry mit Setup-API)
* [x] `lua/mdview/config.lua` (Defaults, user overrides)
* [ ] `lua/mdview/core/session.lua` (Session-Management, state)
* [ ] `lua/mdview/core/events.lua` (Autocommands: BufEnter, BufWritePost, TextChanged)
* [r] `lua/mdview/adapter/runner.lua` (spawn persistent server process via `vim.loop.spawn`)
* [r] `lua/mdview/adapter/ws_client.lua` (WebSocket client zur Kommunikation mit Server)
* [ ] Unit-Tests für Lua-Module schreiben (z. B. mit `busted` oder `plenary`):
  * [ ] Tests für Config Defaults
  * [ ] Tests für Session-Management (stateless expectations)
  * [ ] Tests für Event-Debounce-Logik

Test-Strategie:
* [ ] Lokale Unit-Tests ausführen: `busted` / `plenary.test_harness`
* [ ] Manuell in Neovim: `:edit README.md`, `:MarkdownPreviewStart`, `:MarkdownPreviewStop` testen

---

## Phase B — Minimaler Server (Node.js default; Bun optional später)

Ziel: minimaler HTTP/WS-Server, der einfachen Markdown → HTML Render liefert.

* [x] `src/server/index.ts` (Entrypoint)
* [x] `src/server/server.ts` (HTTP + WebSocket Server)
* [x] `src/server/render.ts` (Markdown → HTML, initial: markdown-it)
* [ ] `src/server/ws-protocol.ts` (Message schema: {type, payload})
* [ ] `src/server/dev-scripts` (start-dev, restart hooks)
* [ ] Tests für Server-Units:
  * [ ] Tests für Render-Funktion (input → expected HTML)
  * [ ] Tests für WS-Protokoll Serialisierung/Deserialisierung
* [ ] E2E-Smoke: Server starten, Curl `GET /render?path=...` → valid HTML

Test-Strategie:
* [ ] Unit tests mit `vitest` oder `jest`
* [ ] Lokaler Start: `npm run dev` / `node ./dist/index.js`
* [ ] Optional: Makefile/Scripts für `start:node` / `start:bun` (Bun only later)

---

## Phase C — Browser Client (TypeScript, WebWorker optional)

Ziel: TypeScript-Client, empfängt WebSocket-Events und patched DOM inkrementell.

* [x] `src/client/index.ts` (WebSocket Verbindung + event handling)
* [ ] `src/client/ui.ts` (DOM-Patch-Logik, incremental DOM / morphdom)
* [ ] `src/client/worker.ts` (optional: WebWorker für heavy tasks)
* [ ] `src/client/styles.css` (Default Theme + Dark/Light)
* [x] `src/client/index.html` (Dev page / client shell)
* [ ] Tests / Lint:
  * [ ] Unit tests für DOM-Patcher (jsdom)
  * [ ] Lint / type checks (tsc + eslint)
* [ ] Manual BROWSER smoke test: `open http://localhost:PORT` und prüfen, ob WS-Connect erfolgreich ist

Test-Strategie:
* [ ] `npm run build:client` und `npm run dev` in Kombination mit Server
* [ ] Browser DevTools: Message Latency, console errors

---

## Phase D — Integration Neovim ↔ Server ↔ Browser

Ziel: End-to-End-Workflow funktioniert: Buffer-Change → Server render → Browser Update.

* [ ] Sicherstellen, dass Lua-Adapter `runner` Server startet und WS-Verbindung aufbaut
* [ ] Implementieren von minimalem Protokoll:
  * [ ] `file_open` event (Neovim → Server)
  * [ ] `file_change` event (Neovim → Server; payload: path OR patch)
  * [ ] `render_update` event (Server → Browser; payload: HTML / patch)
* [ ] Integrationstests:
  * [ ] E2E-Skript: start server → start client (headless) → trigger notify via WebSocket → assert client received `render_update`
  * [ ] Manuelles E2E: in Neovim Datei öffnen/ändern → Browser aktualisiert sich sichtbar
* [ ] Edgecases testen:
  * [ ] große Dateien (performance)
  * [ ] schnelle aufeinanderfolgende Änderungen (debounce)
  * [ ] offline/Server crash recovery (Neovim reconnect)

---

## Phase E — Performance-Optimierungen & WASM POC

Ziel: Verbesserungen nach Profiling, WASM-POC für Parser/Highlighting implementieren.

* [ ] Profiling einrichten (Server: `clinic` / `node --inspect` / Bun profiler; Client: Chrome DevTools)
* [ ] Implementiere Debounce/Coalesce in Core (Lua) und in Server
* [ ] Caching:
  * [ ] file-hash caching (neuer Upload nur bei Hash-Change)
  * [ ] AST / highlight caches serverseitig
* [ ] WASM PoC:
  * [ ] `wasm/markdown-wasm/` initial POC (markdown-wasm package oder Rust→wasm)
  * [ ] Server: laden von WASM-Modul persistent
  * [ ] Client: optional WASM-Highlighting in WebWorker
* [ ] Tests:
  * [ ] Performance-Benchmarks: Time-To-First-Render, Latency nach Save
  * [ ] Regressionstests für POC-Change
* [ ] Optional: implementiere streaming / chunked rendering für sehr große Dateien

---

## Phase F — Feature-Set Ergänzungen & Konfigurationsoptionen

Ziel: Feature-Complete für MVP + Konfigurierbare Runtime (Node / Bun) als Roadmap-Item.

* [ ] Link-Resolving: implementieren, relative Pfade auflösen, Projekt-Root-Erkennung
* [ ] Commands & Config:
  * [ ] `:MarkdownPreviewStart`, `:MarkdownPreviewStop`, `:MarkdownPreviewToggle`
  * [ ] `require('mdview').setup({ server_runtime = "node" | "bun", server_port = 43219, project_root = ... })`
* [ ] Dokumentation:
  * [ ] README: Installationsschritte für Node (Default), Anleitung für Bun (optional)
  * [ ] Architekturdiagramm aktualisieren
  * [ ] API-Dokumentation (EmmyLua / TSDoc)
* [ ] Roadmap-Eintrag: Wechselbare Runtime (M3)
  * [ ] Tests, Docs, & Installer-Checks für Bun
* [ ] Tests:
  * [ ] Cross-platform smoke tests (Linux/macOS, Windows)
  * [ ] CI-Jobs für Node default flow
  * [ ] Optional: separate CI matrix für Bun in Feature-Branch

---

## Phase G — CI, Packaging, Release

Ziel: stabile Releases, Automatisierung, Qualitäts-Safety-Net.

* [ ] CI-Pipeline (GitHub Actions):
  * [ ] Lint (Lua + TS)
  * [ ] Unit Tests (Node + Lua)
  * [ ] Build artifacts (client bundle)
  * [ ] E2E smoke (optional: headless browser)
* [ ] Release Workflow:
  * [ ] Tagging Convention (semver)
  * [ ] Changelog generation (conventional commits)
* [ ] Packaging:
  * [ ] npm package für server/client (optional)
  * [ ] Plugin-Registry Eintragung / Install-Anweisungen
* [ ] Telemetry / optional metrics (nur wenn ausdrücklich benötigt)

---

## Priorisierte Checkliste (Kurzversion, für Sprint-Board)

* [ ] Repo & Struktur initialisieren
* [ ] Core Lua: autocommands + session management
* [ ] Minimal Node Server: render endpoint + WS
* [ ] TypeScript Client: WS connect + DOM patch
* [ ] Integration E2E: Neovim → Server → Browser
* [ ] Unit Tests (Lua, Node, Client)
* [ ] Performance Debounce & Caching
* [ ] WASM POC (server/client)
* [ ] Config API + Commands + Docs
* [ ] CI + Release Pipeline
* [ ] Bun Laufzeit als optionaler Meilenstein (M3)

---

## Zusätzliche Hinweise

* Für Lua-Unit-Tests empfiehlt sich `plenary.nvim` Test-Harness oder `busted` falls unabhängig.
* Für Neovim-spezifische Integrationstests sind Headless-Neovim-Instanzen (nvim --headless) nützlich.
* Für den Client sind `vitest` + `jsdom` oder Playwright für E2E (Headless Chromium) empfehlenswert.
* Behalte Messpunkte (Time-to-render, Latency) in Tests als Gatekeeper für Performance-Regressions.

---

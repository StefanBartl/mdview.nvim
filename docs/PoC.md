# Proof of Concept – Projektbeschreibung

 **Projektname: mdview.nvim**
 Ziel: Entwicklung eines Neovim-Plugins zur browserbasierten Markdown-Vorschau mit Live-Synchronisation, internem Link-Auflösen und hoher Performance.

---

## Table of content

  - [Zielsetzung](#zielsetzung)
  - [Technische Anforderungen](#technische-anforderungen)
  - [Architekturübersicht](#architekturbersicht)
  - [Workflow (Event Flow)](#workflow-event-flow)
  - [Performance-Optimierungen](#performance-optimierungen)
    - [Server-seitig](#server-seitig)
    - [WASM](#wasm)
    - [Client (Browser)](#client-browser)
    - [Kommunikation](#kommunikation)
    - [Neovim Plugin (Lua)](#neovim-plugin-lua)
    - [Metriken zur Erfolgskontrolle](#metriken-zur-erfolgskontrolle)
  - [Roadmap & Meilensteine](#roadmap-meilensteine)
  - [Dokumentation & Standards](#dokumentation-standards)
  - [Lieferumfang des Proof of Concept](#lieferumfang-des-proof-of-concept)
  - [Ausblick](#ausblick)

---

## Zielsetzung

Ein Plugin für Neovim, das:

* Markdown-Dateien rendert und im Browser darstellt.
* Links und Anchors innerhalb des Projekts (innerhalb und zwischen Markdown-Dateien) korrekt auflöst.
* Automatisch aktualisiert wird, wenn die Datei geändert wird oder eine neue Markdown-Datei fokussiert wird.
* Server- und Client-Komponenten enthält, die aufeinander abgestimmt sind, und optional moderne Technologien wie WASM nutzen.
* Dem Benutzer später die Wahl lässt zwischen verschiedenen Laufzeitumgebungen (z. B. Node.js oder Bun) — **Default wird Node.js** sein, um Installationsbarriere gering zu halten.

---

## Technische Anforderungen

* **Markdown Rendering**: Markdown → HTML mit Unterstützung von internen Projektlinks (`[Link](otherfile.md#anchor)`), externen Links, Bildern, CSS-Theming.
* **Live-Synchronisation**: Dateiänderungen (Speichern, Texteingabe) und Buffer-Wechsel in Neovim triggern sofortige Aktualisierung im Browser.
* **Browser-Frontend**: Client im Browser (HTML/TypeScript) mit WebSocket/Schnittstelle zum Server, dynamisches Aktualisieren ohne kompletten Reload.
* **Server-Komponente**: Lokaler HTTP/ WebSocket-Server, der Markdown rendert und Änderungen streamt.
* **Technologie-Stack (vorläufig)**:

  * **Server**: Default → Node.js (mit Option für Bun als späteren Meilenstein).
  * **Client**: TypeScript + WebSocket + optional Highlight.js oder WASM-Highlighting.
  * **Plugin Core (Neovim)**: Lua mit `vim.loop.spawn` oder `uv` APIs, Event-Bus, Autocommands.
  * **Kommunikation**: WebSocket für bidirektionale Updates, geringe Latenz.
* **Performance-Optimierungen** (siehe Abschnitt unten) werden von Anfang an berücksichtigt.

---

## Architekturübersicht

**Architekturstil**: Hexagonal/Mikrokernel – klar getrennte Schichten (Core, Adapter, UI) gemäß Vorgaben in Arch&Coding-Regeln.

| Schicht       | Modul(e)                                                                                         | Aufgabe                                          |
| ------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| Core Layer    | `core/markdown.lua`, `core/session.lua`                                                          | Datei-State, Rendering-Logik, Session-Management |
| Adapter Layer | `adapter/server.js` (Node.js) / optional `adapter/server.ts` (für Bun) <br> `adapter/browser.ts` | Schnittstelle HTTP/WS, Browsersteuerung          |
| UI Layer      | `ui/commands.lua`, `ui/autocmds.lua`, `ui/state.lua`                                             | Neovim Commands, Autocommands, Statusanzeige     |
| Config Layer  | `config/defaults.lua`, `config/user.lua`                                                         | Standardwerte, Konfigurierbarkeit                |
| Utils Layer   | `utils/fs.lua`, `utils/log.lua`, `utils/debounce.lua`                                            | Filesystem, Logging, Event-Debounce etc.         |

---

## Workflow (Event Flow)

1. Nutzer öffnet oder wechselt eine Markdown-Datei in Neovim.
2. Autocommand (z. B. BufEnter / BufWritePost) feuert: Plugin Core erkennt Datei-Pfad.
3. Core ruft den Server über WebSocket/HTTP an oder sendet Event „file_changed“.
4. Server rendert Markdown (evtl. via WASM-Parser) zu HTML und sendet Update an Browser.
5. Browser empfängt via WebSocket und aktualisiert die Darstellung (Patch oder Full‐Reload).
6. Links/Anchors werden relativ zum Projekt-Root aufgelöst, Navigation im Browser wird unterstützt.

---

## Performance-Optimierungen

### Server-seitig

* Persistenter Serverprozess (kein Neustart pro Request).
* Datei-Events debounced/coalesced: mehrere Änderungen werden zusammengefasst.
* WASM-Parser für Markdown (z. B. `markdown-wasm`, Rust → wasm32) persistent instanziert.
* Streaming-Rendering (Chunks statt kompletter Datei) falls nötig.
* Kompression (Brotli/gzip) für Assets und HTML.
* Worker-Pools oder Threads für parallele Verarbeitung.

### WASM

* Release-Optimierung, LTO, ggf. SIMD/Threads nutzen.
* Minimale Module, initial großer Memory-Pool.
* Serverseitig ggf. Native Rust Binär als Alternative, wenn Profilierung Bedarf zeigt.
* Client-seitig WebWorker + WASM für Highlighting/Diagramme.

### Client (Browser)

* WebWorker für Parsing/Highlighting (TypeScript + WASM).
* Incremental-DOM bzw. Patch-Verfahren statt Full innerHTML Replace.
* Virtualisierung bei großen Dokumenten (windowing).
* Caching von ASTs, Highlighting-Ergebnissen pro Datei-Hash.
* Minimalen DOM-Aufbau, CSS containment, requestAnimationFrame für UI-Updates.

### Kommunikation

* WebSocket mit kompaktem Protokoll (z. B. MessagePack) statt JSON wenn Datenvolumen hoch.
* Event Rate Limiting / Backpressure: bei Client-Lag Events coalescen.
* WebSocket Kompression (permessage-deflate) aktivieren.
* Sicher: nur `localhost`‐Binding standardmäßig.

### Neovim Plugin (Lua)

* Einmaliger Server-Process via `vim.loop.spawn`.
* Native FS-Watcher (`vim.loop.fs_event`) statt Polling.
* Debounce Autocommands (TextChanged, BufWritePost) mit wiederverwendbaren Tables.
* Nur minimal notwendige Daten senden (Pfad + Änderungen) statt kompletten Datei‐Komplettupload wenn möglich.

### Metriken zur Erfolgskontrolle

* Time to First Render nach Datei­wechsel (ms)
* Latency nach Save/TextChange (ms)
* CPU/Memory des Servers (Worker)
* UI Frame-Rate / Jank beim Scrollen im Browser
* Bandbreite pro Update (KB)
* Durchsatz: wie viele Docs/Minute gerendert bei Batchbetrieb

---

## Roadmap & Meilensteine

| Meilenstein                              | Beschreibung                                                                                                                                         |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| M1 – Minimal viable plugin               | Neovim Plugin (Lua) + Node.js Server + Browser Client (TypeScript) mit Live-Rendering und Linkauflösung.                                             |
| M2 – Performance Optimierung             | Implementierung von Debounce/Coalesce, Caching, WASM-Parser Server-seitig, Incremental DOM Client-seitig.                                            |
| M3 – Wahl der Laufzeitumgebung           | Nutzer kann wählen zwischen Node.js (default) **oder** optional Bun als Server-Runtime. Dokumentation & Setup-Scripts für Bun werden bereitgestellt. |
| M4 – Erweiterte Features                 | Diagramm-Support (Mermaid), KaTeX, synchrones Scrollen Cursor↔Browser, Multi-Session Support.                                                        |
| M5 – Native Rust/WASM-Backend (optional) | Ersetzen des Markdown-Parsers durch native Rust-Binär oder WASM mit SIMD/Threads für maximale Performance.                                           |

**Default-Laufzeitumgebung:** Node.js – damit keine neue Runtime zwingend installiert werden muss. Bun wird als Option im nächsten Meilenstein (M3) vorgesehen.

---

## Dokumentation & Standards

* Modul- und Funktionsdokumentation mit EmmyLua (Lua-Seiten) und TSDoc (TypeScript-Seiten).
* Einhaltung der Arch&Coding-Regeln (Modularität, SRP, Fehlerhandling, Logging).
* Checkliste, wie in Check.md definiert: Logging, Tests, Cleanup, Performance-Profiling, Platform-Support (Linux/macOS primär, Windows optional).
* Architekturdiagramm, API-Referenz, Designentscheidungen werden dokumentiert.

---

## Lieferumfang des Proof of Concept

1. Neovim Plugin `mdview.nvim` mit Lua-Core, Autocommands, Command-Setup.
2. Node.js Server (TS/JS) mit HTTP/WS Endpunkten, Markdown-Parser, Live-Update.
3. Browser Client (TypeScript) mit WebSocket Verbindung, HTML Rendering, minimalem UI.
4. Dokumentation: Architekturübersicht, API-Referenz, Performance-Messung, Roadmap.
5. Setup & Installationsanleitung (inklusive Konfiguration für Node.js).
6. Tests: Unit-Tests für Core, Integrationstest Client ↔ Server.

---

## Ausblick

Nach erfolgreichem Proof of Concept wird auf Performance-Hochtouren gebracht: WASM, Worker, Edge-Technologien, Alternativ-Runtimes (Bun), Multi-Session Support, erweiterte Features wie Diagramme und synchrones Scrollen.

---

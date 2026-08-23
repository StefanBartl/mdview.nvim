# mdview.nvim — was es gibt

Der vollständige Katalog: **alles, was implementiert ist**, nicht nur das,
was ein Nutzer direkt bedient. Die Mechanik darunter — Caches, Throttling,
Diff-Transport, Lifecycle — steht hier gleichberechtigt, weil sie beim
Weiterentwickeln genauso beantwortet werden muss wie „welches Kommando gibt
es dafür".

| Wo | Inhalt |
| --- | --- |
| **diese Datei** | vollständiger Überblick, user- *und* dev-seitig |
| [`PREVIEW.md`](PREVIEW.md) · [`RENDERING.md`](RENDERING.md) · [`OPERATIONS.md`](OPERATIONS.md) · [`SECURITY.md`](SECURITY.md) | die großen Themen im Detail, im [`FEATURES_FORMAT`](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/FEATURES_FORMAT.md)-Schema |
| [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md) | *warum* etwas so gebaut wurde (Entscheidungs-Log) |
| [`../ROADMAP/ROADMAP.md`](../ROADMAP/ROADMAP.md) | was noch offen ist |

---

## Architektur in einem Absatz

Vier Sprachen, klare Schnitte: **Lua** steuert (Kommandos, Autocmds,
Prozess-Lifecycle), ein **Go**-Relay verteilt (HTTP-Endpoints +
WebSocket/WebTransport-Fanout, kennt weder Dateien noch Puffer), ein
**Rust/WASM**-Modul rendert (Markdown → sanitisiertes HTML, im Browser),
**TypeScript** verdrahtet den Tab. Details:
[`../architecture.md`](../architecture.md).

---

## Preview & Synchronisation

Ausführlich in [`PREVIEW.md`](PREVIEW.md).

- **Live-Preview im Browser** — Puffertext fließt über das Relay in einen
  Browser-Tab, gerendert im Client.
- **Live-Push bei Änderung und beim Speichern** — `TextChanged`/
  `TextChangedI` plus `BufWritePost`.
- **Scroll-Sync Neovim → Browser** und **Reverse-Scroll** Browser → Neovim.
- **Cursor-Marker** — Position aus Neovim im gerenderten Dokument.
- **Zoom**, **Pause/Resume** des Scroll-Syncs, **Overlays** (schwebendes
  TOC), **Breadcrumbs** (Session-Outline).
- **Click-to-Navigate** — Klick auf einen relativen Link öffnet die Datei in
  Neovim statt den Tab wegzunavigieren.
- **Link-Hover-Vorschau** — Bild, Textdatei-Anfang, geparste URL,
  Anker-Abschnitt oder „nicht gefunden". Gegenstück zum In-Editor-Hover in
  markdown.nvim.
- **Standalone-Preview** — läuft ohne (bzw. über) die Neovim-Instanz hinaus,
  auch aus dem Terminal startbar.
- **In-Editor-Preview-Tab** — `:MDView preview-tab`, ganz ohne Relay und
  Browser.

## Rendering

Ausführlich in [`RENDERING.md`](RENDERING.md).

- **comrak + ammonia in einem WASM-Aufruf** — Rendering und Sanitisierung
  sind untrennbar; kein Aufrufer kann HTML bekommen, das die Allowlist
  umgangen hat.
- **Themes**, lazy geladen — ein Theme ist eine CSS-Datei plus ein
  Map-Eintrag.
- **Code-Fence-Highlighting** über Shiki (mit hljs-Pfad), asynchron nach dem
  Einfügen ins DOM.
- **Private Blöcke** — ```` ```private ```` rendert unscharf, per Klick oder
  `:MDView reveal` aufdeckbar.
- **Lokale Bilder** — relative `<img src>` werden auf die `/asset`-Route
  umgeschrieben.
- **Blank-Line-Handling** — Leerzeilen-Abstände als eigene Spacer.

## Betrieb & Diagnose

Ausführlich in [`OPERATIONS.md`](OPERATIONS.md).

- **Installation ohne Toolchain** — vorgebaute Artefakte aus GitHub Releases.
- **`:checkhealth mdview`**, **`:MDView diagnose`** (Vollreport),
  **`:MDView log`** (Plugin-Log), **`:MDView file-log`** (persistentes
  Relay-Log), **`:MDView weblogs`** (Relay-stdout).
- **`lib.nvim` als harte Laufzeitabhängigkeit** — bewusst, kein
  pcall-Fallback-Geflecht.

## Sicherheit

Ausführlich in [`SECURITY.md`](SECURITY.md).

- **Loopback-only Relay** mit Per-Session-Token und Origin-Prüfung.
- **Race-freie Portwahl.**
- **WebTransport-Zertifikats-Pinning.**
- **`/asset` und `/preview`** — beide an das Dokumentverzeichnis gebunden,
  mit Traversal-Prüfung und je eigener Endungs-Allowlist. `/preview` ist
  enger als `/asset`, weil es Dateiinhalt zurückgibt statt Bytes, die der
  Browser als Bild rendert.

---

# Für Entwickler

Ab hier: Mechanik, die kein Kommando hat, aber jede Änderung beeinflusst.

## Readiness-Cache im `ws_client`

`live_push` wickelt **jedes** `TextChanged` in ein `wait_ready` ein. Ohne
Cache hieße das ein `curl /health` pro Tastendruck. `M._ready` merkt sich
einen einmal gesunden Server; `M.reset_ready()` verwirft das beim
Stop/Respawn.

- **Modul:** `lua/mdview/adapter/ws_client.lua` (`wait_ready`, `reset_ready`, `_ready`)
- **Warum:** siehe [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md), BUGS #5 — der
  fehlende `cb(true)` machte den Cache-Bedarf überhaupt erst sichtbar.

## Trailing-Throttle für Live-Pushes

Jeder Push startet einen `curl`-Prozess. Schnelle Edits werden zu **einem
nachlaufenden** Push zusammengefasst statt einem pro Tastendruck.

Wichtig und leicht falsch zu machen: Anders als der Scroll-Sync-Throttle,
der ein Ping einfach fallen lässt, darf hier **nichts verworfen** werden —
ein verschluckter Push hinterlässt eine Preview, die dauerhaft vom Puffer
abweicht. Deshalb wird ein Push im Throttle-Fenster *verschoben*, nicht
gestrichen.

- **Modul:** `lua/mdview/bindings/autocmds/live_push.lua` (`pending_timer`, `cancel_pending`)
- **Config:** `live_push_throttle_ms`; `BufWritePost` wird nie gedrosselt.

## Zeilen-Diff-Transport (experimentell)

Statt des vollen Puffers kann eine Zeilen-Edit-Beschreibung übertragen
werden. Voll-Snapshots bleiben der Normalweg; der Diff-Pfad ist opt-in.

- **Modul:** `lua/mdview/utils/line_diff.lua`, `utils/diff.lua`,
  `utils/diff_granular.lua`; Client: `src/client/render/diffDoc.ts`
- **Config:** `experimental.line_diff` (default aus)
- **Vorsicht:** Ein Diff, der auf einem anderen Basiszustand aufsetzt als der
  Client hat, rendert Unsinn — deshalb der Envelope mit Resync-Pfad.

## Plain-Text-Vorschau für Nicht-Markdown-Dateien (experimentell)

Mit `experimental.any_file` weitet `mdview.config.merge()` `ft_pattern` auf
`{"*"}` — die Neovim-Glob-Ebene feuert dann für jeden benannten Buffer.
`helper/previewable.lua` ist das eigentliche Gate danach (buftype leer,
benannt, nicht binär, nicht mdviews eigener Log-Buffer); ohne
`experimental.any_file` verlangt es zusätzlich `filetype == "markdown"/"md"`
wie bisher. Der Client rendert eine Nicht-Markdown-Datei nicht durch den
WASM-Renderer, sondern als einen einzigen, per Dateiendung eingefärbten
Code-Block (dieselbe `<pre><code class="language-x">`-Form, die comrak für
Fences erzeugt — kostenlos themed über `_base.css`, kostenlos gehighlightet
über den bestehenden hljs/shiki-Dispatcher).

- **Modul:** `lua/mdview/helper/previewable.lua`; Client:
  `src/client/render/fileKind.ts`, `src/client/highlight/languageForPath.ts`,
  `src/client/render/plainText.ts`
- **Config:** `experimental.any_file` (default aus)
- **Vorsicht:** Kein `data-sourcepos` für diese Dateien — Scroll-Sync fällt
  auf die bestehende proportionale Schätzung zurück (siehe
  `main.ts`'s `applyScrollPing`-Fallback), die Cursor-Zeilenleiste zeigt sich
  nicht. Zeilengenaue Parität mit Markdown ist ein möglicher Folgeschritt.

## Dokumentmodell im Client

Ein gemeinsames Modell statt drei eigener Parser: Top-Level-Blöcke mit
`data-sourcepos` (comrak-Sourcemap), daraus die Heading-Outline und die
Zuordnung Zeile ↔ Block.

Genutzt von **TOC-Overlay**, **Scroll-Sync**, **Cursor-Marker** und
**Link-Hover** (Anker-Auflösung). Es geht über `H1`–`H6`-Tags, **nicht**
über `id`-Attribute — der WASM-Renderer erzeugt keine.

- **Modul:** `src/client/render/docModel.ts` (`topLevelBlocks`, `headings`, `governingHeading`)

## Transport-Abstraktion

WebSocket und WebTransport hinter einem Interface; die Fabrik wählt.
WebSocketStream wurde geprüft und verworfen (kleine Text-Updates, kein
Durchsatzproblem) — siehe [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md) BUGS #3.

- **Modul:** `src/client/transport/` (`transport.interface.ts`, `transportFactory.ts`, `websocket.transport.ts`, `webtransport.transport.ts`)

## Per-Dokument-Räume im Relay

Das Relay kennt weder Dateien noch Puffer — nur „hier ist Text für Raum K,
fächere ihn auf". Mehrere offene Dateien kontaminieren sich dadurch nicht
gegenseitig. Live-Puffer und Standalone-Dateiwatcher münden in denselben
`Broadcast`.

- **Modul:** `native/server/internal/relay/registry.go`, `internal/source/watch.go`

## Polling-Bridge Browser → Neovim

Neovim hat keinen WebSocket-Client, und das Relay bleibt ein dummer
Byte-Weiterleiter. Für die Rückrichtung (Klick-Navigation,
Reverse-Scroll) pollt Neovim das Relay im 250-ms-Takt — nur die aktivierten
Endpoints, und der Timer läuft nur, wenn überhaupt einer aktiv ist.

Diese 250 ms sind der Grund, warum manche Browser-Features nicht sinnvoll
sind (etwa PDF-Seitenrendering im Hover, siehe
[`../ROADMAP/ROADMAP.md`](../ROADMAP/ROADMAP.md)).

- **Modul:** `lua/mdview/adapter/inbound_poll.lua`; Server: `relay/nav.go`, `relay/scrollbox.go`

## Autocmd-Lifecycle

Autocmds haben echten Attach/Detach-Lifecycle, Usercmds **nicht** — die
werden einmal bei `setup()` registriert und nie abgebaut. Grund: ein
`:MDViewStop`, das seine eigenen Kommandos mitlöschte, war ein realer Bug.

- **Modul:** `lua/mdview/helper/autocmds_registry.lua`, `bindings/autocmds/init.lua`
- **Warum:** [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md), BUGS #4

## Session- und Prozesszustand

Ein laufender Server wird wiederverwendet; Token-Rotation passiert nur beim
tatsächlichen Spawn. Ein Neustart mit rotiertem Token gegen einen alten
Prozess ergab sonst stille 403er (curl liefert Exit 0 bei HTTP-Fehlern).

- **Modul:** `lua/mdview/core/session.lua`, `core/state.lua`, `adapter/server_args.lua`
- **Warum:** [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md), BUGS #5

## Testebenen

Vier Suiten, je Sprache eine: `vitest` (Client, jsdom), `go test` (Relay,
inkl. der Sicherheitsgrenzen von `/asset` und `/preview`), `cargo test`
(Renderer/Sanitizer), Lua. `npm run test:all` fasst die ersten drei
zusammen.

- **Modul:** `tests/client/`, `native/server/*_test.go`, `native/wasm-render/src/lib.rs` (`#[cfg(test)]`), `tests/lua/`

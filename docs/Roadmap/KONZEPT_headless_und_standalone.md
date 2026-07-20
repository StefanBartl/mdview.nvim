# Konzept: Preview ohne Server, Hintergrund-Instanz und Standalone-Binary

> **Status: umgesetzt** (Abschnitte 2, 3/Stufe A und 4). Nutzerdoku:
> [`docs/standalone.md`](../standalone.md). Konkret gebaut wurden:
> `scripts/minimal_init.lua`, `scripts/mdview-bg.{sh,ps1}`,
> `native/server/internal/source` (`--watch`/`--open`), `:MDView detach`,
> `:MDView standalone` und `standalone.binary_path`.
> Offen geblieben: Abschnitt 1 Option A (statischer HTML-Export) und
> Abschnitt 3.4/Stufe B (eigenes Single-Binary mit `go:embed`).
>
> Dieses Dokument bleibt als Entscheidungsgrundlage bestehen — es begründet,
> *warum* es so gebaut wurde. Der Text unten ist der ursprüngliche Konzeptstand.

> Beantwortet drei zusammenhängende Fragen:
> (1) Lässt sich das Hauptfeature ohne Serverstart anbieten? (2) Lässt sich
> mdview als Hintergrundprozess aus einem Terminal starten
> (`nvim --headless ... file.md`), wahlweise mit Browser-Tab oder als
> separierte, minimale nvim-Instanz? (3) Ist ein experimentelles,
> nvim-unabhängiges Standalone-mdview realistisch, cross-platform, in
> Lua/Go/WASM? Alle drei Antworten bauen auf der bestehenden Architektur auf
> (siehe `docs/architecture.md`) — keine davon erfordert einen Rewrite.

---

## 0. Ausgangslage (Ist-Zustand)

Zur Einordnung, was schon existiert und was neu wäre:

| Baustein | Status heute |
|---|---|
| Go-Relay (`native/server`) | Reiner Byte-Relay: nimmt Markdown-Text per `POST /update` von nvim entgegen, broadcastet per WebSocket. Rendert nichts selbst. Kennt nur die eine Content-Quelle „nvim schickt POST". |
| Rendering (`native/wasm-render`) | Rust/comrak+ammonia → WASM, läuft **im Browser**, ist von der Content-Quelle komplett entkoppelt (bekommt rohen Markdown-Text über WS, ist ihm egal woher). |
| `:MDView preview-tab` | Rendert **ohne** Relay/Browser/WASM — Treesitter-Highlighting einer Spiegel-Buffer in einem neuen nvim-Tab. Einzige heute existierende serverlose Variante. |
| Prozess-Spawning | `lua/mdview/adapter/runner.lua:M.start_server` nutzt `vim.loop.spawn` (libuv), nicht `jobstart`/`vim.system`. Kein `detached`-Flag im Einsatz. |
| Cross-Build | `native/server/.goreleaser.yml` baut den Go-Relay bereits für linux/darwin/windows × amd64/arm64. Reine Build-Infrastruktur, kein Standalone-Produkt. |

Wichtigster Befund: **der Relay weiß nichts von Dateien.** Er kennt nur „hier ist Text für Key X, verteil ihn". Das ist der Hebel für alle drei Punkte unten — die Content-Quelle ist austauschbar, ohne Client oder WASM-Renderer anzufassen.

---

## 1. Hauptfeature ohne Serverstart

**Frage:** Gibt es eine Möglichkeit, das Hauptfeature anzubieten, ohne einen Server zu starten?

**Kurz:** Teilweise ja, schon vorhanden (`:MDView preview-tab`), aber mit reduziertem Funktionsumfang. Eine vollwertige serverlose Variante mit identischem Rendering ist möglich, aber nur mit Kompromissen — WASM braucht zwingend einen Host mit JS-Engine (Browser oder Node), und Websocket-Live-Sync braucht zwingend einen Prozess, der zuhört.

### 1.1 Was „ohne Server" tatsächlich bedeutet

Drei Ebenen, die oft in einen Topf geworfen werden:

1. **Kein eigener Serverprozess** (kein `mdview-server.exe` als Kindprozess) — aber ggf. trotzdem ein Browser-Tab.
2. **Kein Browser** — Rendering bleibt im Terminal/in nvim.
3. **Kein Live-Update-Kanal** — statisches Rendering, das bei jeder Änderung neu angestoßen werden muss.

`preview-tab` erfüllt alle drei: kein Serverprozess, kein Browser, aber auch kein WASM/CSS-Theming — nur Treesitter-Markdown-Highlighting in einem Spiegel-Buffer. Für schnelles Gegenlesen reicht das; für das eigentliche „Hauptfeature" (sauber gerendertes HTML mit Theme, Sanitizing, Scroll-Sync) nicht.

### 1.2 Option A — Statischer Einmal-Export (kein Server, aber Browser)

Der bereits vorhandene Rust/comrak-Renderer läuft aktuell nur als WASM im Browser. Comrak selbst ist aber eine normale Rust-Bibliothek — ein zweites, kleines Rust- oder Go-CLI-Target (`render-once`) könnte Markdown direkt zu einer selbstständigen HTML-Datei rendern (Client-CSS/JS inline gebündelt, kein `<script>`, das auf WebSocket wartet) und diese per `file://` im Standardbrowser öffnen. Kein Serverprozess, kein offener Port, kein Token — aber auch kein Live-Reload: jede Änderung braucht einen neuen Export-Aufruf.

- Aufwand: klein bis mittel (neues Cargo- oder Go-Binary-Target, das den vorhandenen comrak/ammonia-Pfad wiederverwendet, plus ein „inline statt WS" Renderpfad im TS-Client oder ein separates, minimales statisches Template).
- Passt gut als `:MDView export [path]` — nützlich für Sharing/Doku-Export, nicht als Ersatz für die Live-Preview.

### 1.3 Option B — `preview-tab` aufwerten statt neu bauen

Näherliegend: `preview-tab` schrittweise näher an die Browser-Preview heranbringen, ohne die Serverpflicht:

- Aktuell nur Treesitter-Highlighting. Perspektivisch könnte derselbe comrak-Renderer (nativ kompiliert, nicht als WASM) verwendet werden, um zusätzliche Metadaten (z. B. aufgelöste Links, Tabellen-Spaltenbreiten) vorzuberechnen und im Spiegel-Buffer per `extmarks`/virtual text darzustellen — ohne echtes HTML/CSS, aber näher am Endergebnis als reines Syntax-Highlighting.
- Terminal-Grafikprotokolle (Kitty Graphics Protocol, Sixel) wären ein größerer Sprung (eingebettete Bilder/Diagramme im Terminal), aber das ist ein separates, deutlich aufwändigeres Konzept und lohnt nur, falls „ohne Browser" (nicht nur „ohne Server") ein hartes Ziel ist.

**Empfehlung:** Für die gestellte Frage ist `preview-tab` bereits die Antwort „Hauptfeature ohne Server"; wenn mehr Rendering-Treue gewünscht ist, ist Option A (statischer Export) der pragmatischere nächste Schritt, da er den vorhandenen comrak-Pfad direkt wiederverwendet.

---

## 2. Hintergrundprozess-API aus dem Terminal

**Frage:** `nvim +MDView --background "C:\TEST.md"` — mdview als eigenständigen Hintergrundprozess starten, wahlweise mit Browser-Tab oder als separierte, minimale nvim-Instanz (nur nvim + mdview installiert).

Wichtig vorab: `nvim +MDView --background file.md` ist keine gültige nvim-CLI-Syntax (`+cmd` nimmt keine Folge-Flags). Die reale Grundlage ist `nvim --headless -c "<cmd>" file.md`, kombiniert mit einer minimalen Config und einem Detach-Mechanismus. Das lässt sich aber sauber in ein Wrapper-Kommando fassen.

### 2.1 Warum das heute schon fast funktioniert

`:MDView start` startet den Relay bereits als Kindprozess und kann headless laufen — der Server braucht kein GUI, `browser.require_display` blendet den `open`-Schritt bei fehlendem Display bereits kontrolliert aus (siehe `docs/checkpoints/01_checkpoint.md`). Was fehlt, ist nicht neue Funktionalität im Relay, sondern:

1. Ein **Startkommando von außen** (aus einem Terminal, nicht aus einer laufenden nvim-Instanz).
2. Eine **minimale, isolierte Config**, die nur `mdview.nvim` (+ dessen `lib.nvim`-Abhängigkeit) lädt, statt der vollen Nutzer-Config.
3. Ein **Detach**, damit der Prozess den startenden Terminal überlebt.

### 2.2 Vorgeschlagene Invocation

```sh
# Minimalform: eigener, isolierter Prozess, headless, mit fester Minimal-Config
nvim --headless -u <mdview-repo>/scripts/minimal_init.lua \
     -c "MDView start" "C:\TEST.md"

# Äquivalent als schlanker Wrapper (neues, optionales CLI-Skript im Repo):
mdview-bg "C:\TEST.md"                 # Browser-Tab (default open_mode)
mdview-bg --no-browser "C:\TEST.md"    # nur Relay, kein Tab (z. B. für externe Clients)
```

`scripts/minimal_init.lua` wäre eine ~10-Zeilen-Datei: `rtp` nur um `mdview.nvim` und `lib.nvim` erweitern, `require("mdview").setup({})`, fertig — genau die „eigene isolierte Instanz, wo nur nvim und mdview installiert sind" aus der Anfrage. Das ist im Kern identisch zum bereits vorhandenen Testharness-Pattern (`b1151c1 test(harness): resolve lib.nvim instead of requiring it on the invocation's rtp` — dort existiert schon eine funktionierende Minimal-RTP-Auflösung, die sich wiederverwenden lässt).

`mdview-bg` selbst wäre ein dünnes Shell/PowerShell-Skript (analog zu `dev:server` in `package.json`), das:

- die Zieldatei zu einem absoluten Pfad auflöst,
- `nvim --headless -u minimal_init.lua -c "MDView start" <file>` **detached** startet (Unix: `setsid ... &`; Windows: `Start-Process -WindowStyle Hidden`),
- optional `--no-browser` als `browser.browser_autostart=false` in die minimal_init durchreicht.

### 2.3 Zwei Betriebsarten für den Hintergrundprozess

| Modus | Verhalten | Anwendungsfall |
|---|---|---|
| **Mit Browser-Tab** (default) | Headless-nvim startet Relay + öffnet Browser-Tab wie gewohnt, läuft danach im Hintergrund weiter und pusht Änderungen (`live_push` Autocmd funktioniert headless identisch). | Schnelles „einmal aufrufen, danach vergessen" — Preview bleibt offen, Terminal ist wieder frei. |
| **Ohne Browser** (`browser.browser_autostart=false`) | Nur Relay + WS-Endpoint laufen; kein Tab wird geöffnet. | Fernzugriff (Preview von einem anderen Rechner im selben Netz öffnen), oder Vorstufe für den Standalone-Client aus Abschnitt 3. |

### 2.4 Was technisch neu wäre

- **Detach-Flag beim Spawn**: `runner.lua`s `vim.loop.spawn` müsste um `detached = true` erweitert werden, *wenn* der Detach aus einer laufenden nvim-Instanz heraus passieren soll (Abschnitt 4). Für den externen Terminal-Aufruf (`mdview-bg`) übernimmt das Betriebssystem/die Shell den Detach, nvim selbst braucht dafür nichts Neues.
- **`minimal_init.lua`**: neue, kleine Datei im Repo (kein Plugin-Code, nur Bootstrap).
- **Wrapper-Skript(e)**: `scripts/mdview-bg.sh` + `scripts/mdview-bg.ps1`, dünn, keine Logik dupliziert — ruft nur `nvim` mit den richtigen Flags auf.
- **Kein Eingriff in den Relay/Client nötig** — die gesamte Änderung ist Prozessorchestrierung, keine Protokolländerung.

---

## 3. Experimentelles Standalone-mdview (ohne nvim)

**Frage:** Machbarkeit eines eigenständigen, cross-platform mdview — Lua, Go, WASM als Kandidaten.

### 3.1 Kernidee: den Relay um eine zweite Content-Quelle erweitern

Der Relay kennt heute genau eine Content-Quelle: `POST /update` von nvim. Für Standalone-Betrieb braucht er eine zweite, alternative Quelle — **Filesystem-Watching** — die intern denselben `registry.Broadcast(key, content)`-Pfad füttert, den `handleUpdate` in `native/server/main.go:171` heute per HTTP füllt. Client, WASM-Renderer, WebSocket-Framing, Sanitizing — alles bleibt unverändert, weil die Registry nicht weiß (und nicht wissen muss), ob der Text von nvim oder von einem Dateisystem-Watcher kommt.

```
Heute:      nvim (Buffer-Events) --HTTP POST /update--> Registry --WS--> Browser/WASM
Standalone: fsnotify (Datei-Events) --Go-Funktionsaufruf--> Registry --WS--> Browser/WASM
```

### 3.2 Sprachwahl: Go, Lua, WASM im Vergleich

| Kandidat | Eignung als CLI-Host für Standalone-mdview |
|---|---|
| **Go** | Bereits die Implementierungssprache des Relays. Hat mit `internal/relay` schon 90 % der nötigen Logik (Registry, WS, Auth, Static-File-Serving). `fsnotify` ist eine etablierte, cross-platform Bibliothek (linux/darwin/windows). `go:embed` erlaubt, den gebauten Client (`dist/client/`) **in die Binary einzubetten** — echtes Single-Binary-Deployment ohne externe Assets. Cross-Compile-Pipeline (`goreleaser`) existiert bereits für alle drei Zielplattformen. **Klarer Favorit.** |
| **Lua** | Kein produktionsreifer, cross-platform Lua-Standalone-HTTP-Server+Filewatcher-Stack ohne externe Runtime (LuaJIT+luv, OpenResty, o. ä.) — das wäre faktisch eine neue Abhängigkeitskette parallel zu Go, ohne etwas wiederzuverwenden. Innerhalb von nvim ist Lua bereits die richtige Wahl (das ist der Plugin-Code selbst); als *nvim-unabhängiger* Prozess bringt Lua keinen Vorteil gegenüber Go, nur zusätzlichen Betriebsaufwand. **Nicht empfohlen als Host.** |
| **WASM** | WASM ist kein CLI-Host — es braucht selbst einen Host-Runtime (Browser, Node, oder ein WASI-Runtime wie Wasmtime als zusätzliche Abhängigkeit). Der bestehende WASM-Renderer bleibt aber unverändert im Spiel: er läuft weiterhin *im Browser*, den der Standalone-Go-Prozess bedient — nur die Content-Zulieferung ändert sich, nicht das Rendering. Eine WASI-Variante des Relays selbst wäre nur relevant für Sandbox-/Plugin-Host-Szenarien (z. B. Einbettung in einen anderen Editor), die hier nicht gefragt sind. **Bleibt wie heute: Rendering-Layer, nicht Prozess-Host.** |

### 3.3 Vorgeschlagene Architektur

Neues Build-Target `mdview-standalone` (eigenes `main` in `native/server/cmd/standalone/` oder ein `--watch`-Flag direkt am bestehenden `mdview-server`, siehe 3.4), das:

1. **Datei-Argument statt Token/nvim-Kopplung**: `mdview <file.md> [--port 43219] [--theme dark] [--no-open]`.
2. **fsnotify-Watcher** auf die Datei (und optional deren Verzeichnis für relative Links/Bilder), der bei Änderungen den Dateiinhalt liest und `registry.Broadcast(key, content)` direkt aufruft — kein HTTP-Hop, da alles im selben Prozess läuft.
3. **`go:embed` für `dist/client/`**: Client-Bundle + WASM-Renderer werden zur Build-Zeit in die Binary eingebettet, `--web-root` entfällt für den Standalone-Fall. Ergebnis: eine einzelne ausführbare Datei pro Plattform, kein `dist/`-Verzeichnis nötig.
4. **Token**: lokal generiert wie heute (`gen_token`-Äquivalent in Go), da weiterhin loopback-only — keine Sicherheitsabweichung vom bestehenden Modell.
5. **Browser-Öffnen**: dieselbe Cross-Platform-`xdg-open`/`open`/`start`-Logik, die aktuell in Lua (`lua/mdview/adapter/browser/`) liegt, bräuchte ein kleines Go-Äquivalent (paketierte Libraries wie `pkg/browser` existieren dafür bereits).

### 3.4 Zwei Ausbaustufen (Aufwand vs. Nutzen)

| Stufe | Beschreibung | Aufwand |
|---|---|---|
| **A — Flag am bestehenden Relay** | `mdview-server --watch <file>` als zusätzlicher Modus neben `--token`-basiertem nvim-Betrieb. Kein neues Binary, minimal-invasiv. | Klein: neues `internal/source`-Package (fsnotify-Watcher → `registry.Broadcast`), ein neues Flag, keine bestehenden Codepfade angefasst. |
| **B — Eigenes `mdview` Single-Binary** | Separates Build-Target mit `go:embed`, eigenem Browser-Opener, eigenem CLI-Interface (`mdview file.md`, kein nvim-Vokabular wie `--token`). Klar als eigenständiges Produkt vermarktbar/dokumentierbar. | Mittel: neues `cmd/`-Verzeichnis, `goreleaser`-Konfig um ein zweites Artefakt erweitern, eigene Doku (`docs/standalone.md`). |

**Empfehlung:** mit Stufe A als experimentellem Flag beginnen (schnell verifizierbar, nichts Bestehendes gefährdet), bei Bewährung nach Stufe B überführen.

### 3.5 Was explizit gleich bleibt

- Relay-Protokoll (WS-Framing, `\x01`–`\x05`-Präfixe), Client, WASM-Renderer: **unverändert.**
- Sicherheitsmodell (loopback-only, Token, Origin-Check): **unverändert**, nur die Token-Erzeugung wandert von Lua nach Go für den Standalone-Fall.
- Kein Einfluss auf den nvim-Plugin-Pfad — Standalone ist ein zusätzliches Build-Target, kein Ersatz.

---

## 4. Beide Startarten aus einer laufenden nvim-Instanz heraus

**Frage:** Beide Möglichkeiten (Hintergrund-nvim, Standalone-Binary) sollen auch aus einer laufenden nvim-Instanz per Usercmd auslösbar sein — „starte das Gleiche eben in einer neuen Instanz".

Naheliegend als zwei neue Routen im bestehenden `:MDView`-Routing (`lua/mdview/bindings/usrcmds/init.lua:54`), analog zu `start`/`stop`:

```lua
{ path = { "detach" },
  desc = "Start a detached, minimal-config nvim --headless instance previewing this file, then keep this instance untouched",
  run  = function(ctx) detach.run(ctx.rest) end },

{ path = { "standalone" },
  desc = "Start the standalone mdview binary (no nvim) for this file, once it exists",
  run  = function(ctx) standalone.run(ctx.rest) end },
```

- **`:MDView detach`**: baut auf `runner.lua`s Spawn-Pattern auf, aber mit `detached = true` im `vim.loop.spawn`-Options-Table (libuv unterstützt das nativ) und dem Kommando aus Abschnitt 2.2 (`nvim --headless -u minimal_init.lua -c "MDView start" <aktuelle Datei>`). Die aufrufende Instanz bleibt unverändert weiterlaufen — es wird ein komplett zweiter, unabhängiger Prozess, der auch nach `:qa` der ersten Instanz weiterläuft.
- **`:MDView standalone`**: sobald 3.4/Stufe A oder B existiert, ein einfacher `vim.loop.spawn` auf den `mdview-standalone`-Binary-Pfad (neues Config-Feld `standalone.binary_path`, Auto-Download analog zum bestehenden `install.lua`-Mechanismus für `mdview-server.exe`) — kein nvim in der Prozesskette mehr, sobald der Aufruf abgesetzt ist.
- Gemeinsame Voraussetzung: der Spawn-Helper in `adapter/runner.lua` bräuchte ein `detached`-Options-Feld (heute nicht gesetzt, da der Relay-Kindprozess bewusst an die aktuelle nvim-Instanz gebunden ist und beim `VimLeavePre`-Autocmd mitbeendet wird — für `detach`/`standalone` ist genau das *nicht* gewünscht, daher eigener Codepfad statt Wiederverwendung von `start_server`).

---

## 5. Zusammenfassung / Priorisierung

| # | Vorhaben | Aufwand | Risiko für Bestehendes |
|---|---|---|---|
| 1 | `preview-tab` bleibt die serverlose Antwort; ggf. Option A (statischer Export) ergänzen | klein–mittel | keins (additiv) |
| 2 | `mdview-bg`-Wrapper + `minimal_init.lua` für externen Terminal-Start | klein | keins (reine Prozessorchestrierung, kein Protokoll-/Codepfad-Eingriff) |
| 3 | `--watch`-Flag am Relay (Stufe A) als Fundament für Standalone | klein–mittel | keins, wenn als separater Codepfad (`internal/source`) implementiert |
| 4 | `:MDView detach` / `:MDView standalone` als neue Routen | klein (Detach-Flag im Spawn-Helper) | gering, sofern als eigener Codepfad neben `start_server` gehalten |

Reihenfolge 2 → 4(detach) → 3 → 4(standalone) ergibt bei jedem Schritt ein eigenständig nutzbares, verifizierbares Zwischenergebnis, ohne dass ein Schritt die vorherigen Architekturentscheidungen revidiert.

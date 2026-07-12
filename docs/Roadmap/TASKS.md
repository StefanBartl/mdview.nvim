# mdview.nvim — Aufgaben, nach Aufwand sortiert

> Konsolidierte, aktuelle Task-Liste (Stand: nach Go/Rust-Rewrite + Browser-
> Modi + GitHub-Theme). Ersetzt die verstreuten, teils veralteten Listen in
> `Meilensteine.md`, `Meilensteine_2.md`, `WebTransportAPI/*`,
> `Server/utils/codec.md` und `checkpoints/01_checkpoint.md` (alle vor dem
> Rewrite geschrieben, referenzieren Node.js/markdown-it/Bun/WebTransport und
> gelöschte Dateien — siehe deren OUTDATED-Banner).
>
> Erledigte Punkte und ihre Begründungen stehen weiterhin in `Roadmap.md`.
> Diese Datei listet nur **offene** Arbeit, gruppiert nach Aufwand.

---

## Quick Wins (Minuten, hoher Nutzen)

- [ ] **Ersten GitHub-Release `v0.1.0` schneiden.** Es existiert noch kein
  einziger Release → `:MDViewStart` schlägt für jeden fehl, der die Binary
  nicht manuell in den Cache legt (`curl exit 22` auf `checksums.txt`). Die
  CI-Pipeline (`.github/workflows/ci.yml`, `release`-Job) baut+publisht alles
  automatisch bei Tag-Push: `git tag v0.1.0 && git push origin v0.1.0`.
  Danach funktioniert der Auto-Download für alle Plattformen.
- [x] **Weitere Client-Themes** neben `github` hinzugefügt: `dark-dimmed`
  (GitHubs gedämpftes Dark-Theme) und `plain` (neutral, ohne Akzentfarben).
  Gemeinsame Struktur in `src/client/themes/_base.css` extrahiert (jedes Theme
  `@import`iert sie und definiert nur noch seine `--md-*`-Palette); Registrierung
  in `THEME_LOADERS` (main.ts). Auswahl über `browser.theme` bzw. `?theme=`.
- [x] **`:MDViewToggle`**-Command (Start/Stop in einem) — dünner Dispatcher über
  die bestehenden `:MDViewStart`/`:MDViewStop`-Pfade, leitet Start-Args
  (Datei/`cwd=`) beim Starten weiter.

## Leicht

- [x] **`:MDViewTheme <name>`**: Theme zur Laufzeit umschalten — validiert gegen
  die bekannten Themes, setzt `browser.theme` in der Live-Config und öffnet die
  Preview neu (neuer Tab im `default`-Modus). Ohne Argument: aktuelles Theme.
- [x] **README + vimdoc** um `browser.open_mode`, `browser.theme` und die
  Trade-offs (Auto-Close nur im „isolated"-Modus) erweitert — plus neue
  Commands-Tabellen (README, `doc/mdview.txt`, `docs/BINDINGS.md`) und ein
  lib.nvim-Hard-Dependency-Hinweis in `:checkhealth`.
- [x] **Line-Diff-Transport reaktiviert** (opt-in `experimental.line_diff`,
  default false). Der alte `utils/diff_granular.lua` (Myers) war fehlerhaft
  (verlor echte Änderungen), daher neuer, korrekter Prefix/Suffix-Diff
  `utils/line_diff.lua` (Round-Trip headless verifiziert). Wire: versionierte
  `\x03`-JSON-Envelopes — Full-Snapshots über `/update` (LastPayload, Late-Join),
  Diffs über neuen `/diff`-Endpoint (ephemer). Client (`src/client/render/
  diffDoc.ts`) baut den Volltext wieder auf und rendert; bei Versions-Mismatch
  wartet er auf den nächsten Full-Snapshot (Save + alle 25 Edits) → self-healing,
  Relay bleibt byte-dumm. Vitest deckt Full/Diff/Desync/Recovery/Deletion ab.
  Hinweis: Rendering bleibt Volldokument (comrak), der Gewinn ist auf Loopback
  daher moderat (Transport, nicht Render) — deshalb opt-in.

## Mittel

- [x] **Kooperatives Browser-Schließen im „default"-Modus.** Umgesetzt: neuer
  token-gated `POST /close`-Endpoint (Go) broadcastet ein `\x02`-getaggtes
  Close-Signal an alle Rooms (`Registry.BroadcastAllEphemeral`, Test
  `TestRegistry_BroadcastAllEphemeralReachesEveryRoomWithoutTouchingLastPayload`).
  Der Client ruft bei `\x02` `window.close()` auf. `:MDViewStop` sendet das
  Signal (blockierendes curl mit kurzem Timeout) BEVOR der Relay-Prozess
  gekillt wird — sonst würde die Nachricht mit dem Shutdown rennen. Damit
  schließt sich der Tab auch im default-Modus (ohne Prozess-Handle).
- [x] **Click-to-navigate** (Wunschliste #3, opt-in `experimental.click_navigate`):
  Weg (B) umgesetzt — Server→Neovim-Bridge über eine token-gated `/nav`-Queue
  (`native/server/internal/relay/nav.go`): der Client fängt Klicks auf relative
  Links ab (`src/client/render/clickNav.ts`) und POSTet den href; Neovim pollt
  `GET /nav` (`lua/mdview/adapter/nav_poll.lua`), löst den Pfad relativ zum
  Quelldokument auf und öffnet ihn per `:edit` — die Preview folgt dann über
  `browser.behavior`. Externe Links/Anker/absolute Pfade bleiben dem Browser
  überlassen. Getestet: Go-Queue-Unit-Test, vitest für die Link-Entscheidung,
  und ein echtes End-to-End (Relay + headless nvim öffnet die verlinkte Datei).
- [x] **Browser→nvim-Scrolling** (opt-in `experimental.reverse_scroll`,
  Rückrichtung des nvim→Browser-Sync): Client POSTet seine Scroll-Ratio an den
  neuen `/scrollback`-Endpoint (single-slot, consume-once); der Inbound-Poller
  (`inbound_poll.lua`, aus `nav_poll` erweitert) holt sie und bewegt den Cursor
  proportional im Fenster der Datei. Feedback-Loop auf beiden Seiten unterdrückt
  (Client: `scrollSuppressUntil` nach eingehendem Ping; nvim:
  `scroll_sync.suppress()` um den programmatischen Cursor-Move). Bewusst
  opt-in, weil Polling einen kleinen Lag bedeutet (nvim hat keinen Push-Kanal
  zurück). Getestet: Go-ScrollBox-Unit-Test, End-to-End (Relay + headless nvim
  bewegt Cursor), headless-Spec für die Cursor-Mathematik.
- [x] **Buffer-Wechsel-Verhalten konfigurierbar** (`browser.behavior =
  "reuse" | "new_tab" | "manual"`, default `reuse`; Wunschliste #2): neue
  Autocmd-Gruppe `bindings/autocmds/buffer_switch.lua` reagiert auf BufEnter.
  `reuse` routet den aktiven Buffer in den Room des offenen Tabs (State-Feld
  `preview_key`, gesetzt beim Browser-Open, geleert beim Stop) — der eine Tab
  folgt dir; `new_tab` öffnet pro Datei einen eigenen Tab (einmalig, respektiert
  `browser_autostart`); `manual` tut nichts. Kein Regressionsrisiko für den
  Einzeldatei-Fall (dort `preview_key == path`). Headless verifiziert (alle vier
  Routing-Fälle).

## Schwer / Größere Vorhaben

- [ ] **Externe Renderer-Frontends (opt-in).** Wunsch: Dokument an eine externe
  Website / einen alternativen Renderer schicken (VSCode-Web-artig o. ä.).
  Realität: eine beliebige Dritt-Site empfängt unseren Live-Content nicht — sie
  müsste unser WS-Protokoll sprechen. Machbare Varianten: (a) `browser.open_url`
  öffnet bereits jede URL (Escape-Hatch, bekommt aber keine Live-Updates);
  (b) pluggable `--web-root` / alternatives Client-Bundle, das sich mit unserem
  Relay verbindet. **Privacy-Hinweis:** echtes Senden an einen Dritt-Server
  widerspricht dem „loopback-only, nichts verlässt den Rechner"-Sicherheitsmodell
  (siehe |mdview-security|) — nur als bewusstes opt-in mit klarer Warnung.
- [ ] **Fokus nach `:MDViewStart` erzwingen** (Browserfenster in den
  Vordergrund). Kein plattformübergreifendes API; nur über fragile OS-Hacks
  (`wmctrl`, PowerShell, AppleScript). Zurückgestellt.
- [~] **WebTransport als opt-in Zukunftstechnologie.** Client-Seite umgesetzt
  und getestet: `experimental.webtransport` (Config) → `&transport=webtransport`
  (Browser-URL) → Factory mit Feature-Detection + automatischem WebSocket-
  Fallback (`src/client/transport/webtransport.transport.ts`,
  `transportFactory.ts`, Unit-Tests in `tests/client/transportFactory.test.ts`).
  **Offen (dokumentiert):** der HTTP/3-Relay-Backend (quic-go/webtransport-go,
  self-signed Cert + Hash-Delivery, `/wt`-Handler auf `relay.Registry`) — bis
  dahin fällt das Opt-in transparent auf WebSocket zurück. Vollständiges Design:
  `docs/Roadmap/WebTransportAPI/DESIGN.md`. (Ersetzt den früheren „bewusst
  verworfen"-Merker — auf ausdrücklichen Wunsch als opt-in wiederaufgenommen.)

## Testing / Hygiene

- [~] **Lua-Unit-Tests** (busted): erste echte Spec `tests/lua/line_diff_spec.lua`
  für das reine `utils/line_diff`-Modul (Shape + Round-Trip mit derselben
  Splice-Semantik wie der Client), plus `.busted`-Config (lpath). Weitere Module
  (Config-Merge, buffer_switch-Routing) brauchen den `vim`-Global → gehören in
  einen headless-nvim-Runner statt plain busted; als Muster offen.
- [x] **CI: busted-Job** führt jetzt echte Specs aus — busted wird via luarocks
  installiert (fehlte vorher, daher wurde der Schritt immer übersprungen) und
  `busted tests/lua` läuft die Specs mit dem `.busted`-lpath. `.luacheckrc`
  kennt jetzt die busted-Globals für Spec-Dateien.
- [ ] **filetree.nvim-Integration** (fremdes Repo): auf einer Markdown-File-Node
  ein Usrcmd/Keymap anbieten, das die Datei direkt via mdview öffnet. Gehört in
  `filetree.nvim`, nicht hierher — nur als Cross-Repo-Merker.

---

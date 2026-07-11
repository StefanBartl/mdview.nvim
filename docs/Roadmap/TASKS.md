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
- [ ] **Line-Diff-Transport reaktivieren oder final entfernen.** `core/events.lua`,
  `utils/diff*.lua`, `core/session.compute_line_diff` sind dormanter Code aus
  der Vor-WASM-Zeit. Entscheidung: entweder an den Client anschließen (Diffs
  statt Volltext senden — spart Bandbreite bei großen Dateien) oder löschen.
  Aktuell nur `test/`-Harness nutzt sie.

## Mittel

- [ ] **Kooperatives Browser-Schließen im „default"-Modus.** Aktuell kann
  mdview den Tab im normalen Browser nicht schließen (kein Prozess-Handle) →
  `browser_autoclose`/`stop_on_browser_exit` sind im default-Modus No-ops.
  Lösung (markdown-preview.nvim-Muster, siehe
  `markdown_preview/browser/tab.md`): Relay sendet ein `close`-WS-Event an die
  Room-Clients, Client macht `window.close()`. Dann funktioniert Auto-Close
  auch ohne isoliertes Profil.
- [ ] **Click-to-navigate** (Wunschliste #3): Klick auf einen relativen Link in
  der Preview lädt die Zieldatei. Zwei gangbare Wege: (B) Client schickt per WS
  eine Nachricht an Neovim, das die Datei liest und pusht — braucht eine
  Server→Neovim-Bridge; (C) Relay serviert Dateien beschränkt auf den
  Projekt-Root (`/file?path=...` mit Traversal-Schutz). C ist einfacher, wenn
  der Server im Projekt-CWD läuft.
- [ ] **Browser→nvim-Scrolling** (Rückrichtung des bereits umgesetzten
  nvim→Browser-Sync). Client sendet Scroll-Position per WS, ein
  Server→Neovim-Kanal bewegt den Cursor/Viewport. Braucht dieselbe Bridge wie
  Click-to-navigate (B).
- [ ] **Buffer-Wechsel-Verhalten konfigurierbar** (`browser_behavior =
  "reuse" | "new_tab" | "manual"`, Wunschliste #2): beim Wechsel des aktiven
  Markdown-Buffers entweder denselben Tab aktualisieren, einen neuen öffnen
  oder nichts tun.

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
- [ ] **WebTransport statt WebSocket.** Für kleine Text-Updates kein Mehrwert,
  erzwingt TLS auch auf localhost. Bewusst verworfen (Roadmap BUGS #3) — hier
  nur als „nicht verfolgen"-Merker.

## Testing / Hygiene

- [ ] **Lua-Unit-Tests** (busted/plenary) für Config-Merge, Session, Live-Push,
  Browser-URL-Bau. Aktuell nur Go- (relay) und Rust- (render) Tests + manuelle
  headless-E2E-Skripte.
- [ ] **CI: busted-Job** tatsächlich Specs ausführen lassen (die lib.nvim-
  Dependency wird schon geklont, aber es gibt noch keine echten Specs).
- [ ] **filetree.nvim-Integration** (fremdes Repo): auf einer Markdown-File-Node
  ein Usrcmd/Keymap anbieten, das die Datei direkt via mdview öffnet. Gehört in
  `filetree.nvim`, nicht hierher — nur als Cross-Repo-Merker.

---

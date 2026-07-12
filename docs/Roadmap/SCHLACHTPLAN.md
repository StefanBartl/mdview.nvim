# Schlachtplan — Feedback-Runde nach v0.1.0

> Konsolidierte Analyse + Umsetzungsplan aus dem Nutzer-Feedback (2026-07-12).
> Priorisiert P0 (Bug/Blocker) → P1 (wichtig) → P2 (größer/optional). Jeder
> Punkt: **Symptom → Ursache → Fix → Aufwand**. Erledigtes wandert nach
> `Roadmap.md`.

---

## P0 — Bugs, klein & hoher Nutzen

### ✅ 1. Config schluckt falsch platzierte Keys stillschweigend — ERLEDIGT
- **Ursache:** `line_diff`/`click_navigate`/`reverse_scroll` liegen unter
  `experimental.*`; der Merge legte unbekannte Top-Level-Keys still an → Flags
  blieben `false` → `&nav=1` nie an die URL → Features inaktiv (Wurzel des
  „kein Unterschied" UND des click-navigate-404).
- **Fix:** `config.validate()` warnt in `setup()` (vor dem Merge) vor unbekannten
  Keys, inkl. „did you mean `experimental.click_navigate`?"-Vorschlag.
  `experimental.*` bleibt (dein Wunsch), bis die Features rund laufen.

### ✅ 2. Browser-Tab bleibt bei `:qa!` offen — ERLEDIGT
- **Ursache:** `vim_leave.lua` rief nur `runner.stop_server()`, nicht den
  `/close`-Broadcast → Tab blieb offen (obwohl der Content ohne nvim eingefroren
  ist).
- **Fix:** `vim_leave` sendet jetzt `ws_client.send_close()` (blockierendes curl)
  VOR dem Kill → Tab schließt sich. Schließt nebenbei auch alte Tabs beim Quit,
  was den stale-tab-Fall von #3 entschärft.

### ✅ 3. click_navigate: 404 + Verbindungsverlust — GEKLÄRT (Client korrekt)
- **Befund:** Der Client ist **beweisbar korrekt** — 4 jsdom-Tests
  (`tests/client/clickNav.dom.test.ts`) zeigen: relativer Link wird abgefangen
  (preventDefault + POST /nav), externe/Ctrl-Klicks nicht. Der relative `href`
  überlebt die Sanitisierung (`<a href="./docs/PoC.md" …>`, Rust-Test
  `keeps_relative_link_href`), und der Launcher hängt `&nav=1` korrekt an
  (verifiziert).
- **Ursache deines 404:** **stale Tab** — der offene Tab wurde gestartet, als das
  Flag noch `false` war (oder Config editiert ohne Reload) → seine URL hatte kein
  `?nav=1` → keine Interception. Mit #2 (Close beim Quit) verschwinden alte Tabs
  jetzt beim Beenden.
- **So testen:** `:MDViewStop`, alle mdview-Tabs schließen, `experimental.
  click_navigate = true` setzen, **nvim neu starten**, `:MDViewStart` → im Tab
  prüfen dass die URL `&nav=1` enthält (`:MDViewDiagnose` zeigt sie) → Link klicken.
- **Optional-Härtung (offen, klein):** Windows-Backslash-Pfade
  (`.\docs\PoC.md`) im Client zu `/` normalisieren.

---

## P1 — wichtig

### 4. Cursor-Sync ungenau (Zeile landet zu weit oben / außerhalb)
- **Symptom:** Cursor in letzte Zeile → Browser scrollt, Zielzeile ist ganz oben,
  sogar über den sichtbaren Bereich hinaus.
- **Ursache:** `applyScrollPing` mappt **linear** `ratio=(line-1)/total` auf
  `scrollTop`. Gerenderte HTML-Höhe ≠ Quellzeilen (Headings, Codeblöcke,
  Tabellen verzerren) → systematischer Versatz.
- **Fix (proper):** comrak **sourcepos** aktivieren (`options.render.sourcepos =
  true`) → jedes Blockelement bekommt `data-sourcepos="startLine:…"`. Client
  mappt die Cursor-Zeile auf das nächstgelegene Element und `scrollIntoView`
  ({block:'center'} oder mit kleinem Top-Offset) statt der Ratio-Rechnung.
  Ammonia muss `data-sourcepos` durchlassen (Allowlist erweitern).
- **Aufwand:** mittel (Rust-Option + Client-Mapping + Ammonia-Attr).

### 5. Code-Fence-Syntax-Highlighting fehlt (Quellcode weiß)
- **Symptom:** ```` ```lua ```` rendert ohne Highlighting, alles weiß.
- **Ursache:** comrak gibt nur `<pre><code class="language-lua">` aus, **kein**
  Highlighting. color_my_ascii.nvim highlightet im nvim-Buffer (Highlight-Gruppen)
  → **nicht** als HTML → nicht zum Browser spiegelbar. Muss client-seitig sein.
- **Fix:** Client-seitiger Highlighter, gebündelt (CSP verbietet CDN):
  - **Option A – highlight.js** (klassенbasiert, leicht): nach jedem Render
    `pre code[class^="language-"]` durchlaufen und highlighten. Themes als CSS.
    Läuft nach dem Sanitize (WASM→innerHTML), fügt vertrauenswürdige Spans hinzu
    → kein Sanitize-Problem. **Empfohlen** (klein, viele Themes).
  - **Option B – Shiki/syntect (TextMate)**: exakte VSCode-Themes, aber schwer
    (Grammatiken groß). Nur wenn „echte VSCode-Themes" Priorität haben.
  - Verknüpft mit P1-6 (Themes): highlight.js-Theme + Markdown-Chrome-Theme
    zusammen ausliefern.
- **Aufwand:** mittel. **Design-Entscheidung nötig:** A vs. B.

### 6. Mehr Themes (tokyonight, catppuccin, hell, VSCode)
- **Symptom:** nur `github`, `dark-dimmed`, `plain`.
- **Fix:** Pro Theme = Markdown-Chrome-Palette (`_base.css` + Variablen) **plus**
  passendes Code-Highlight-Theme (aus P1-5). Kandidaten: `tokyonight`,
  `catppuccin` (mocha/latte), ein neutrales helles (`light`), VSCode
  (`vscode-dark`/`vscode-light`). Bei Shiki (B) kämen VSCode-Themes „gratis".
- **Aufwand:** mittel, iterativ (pro Theme klein).

### 7. checkhealth ausbauen
- **Symptom:** deckt nur Env + Assets ab.
- **Fix:** ergänzen: laufende Session (proc/attached/token/health), belegter
  Port, Browser-Auflösung (open_mode/resolved cmd/display), Config-Sanity
  (unbekannte Keys, aktive experimental-Flags), Client-Bundle-Integrität
  (index.html + wasm vorhanden), lib.nvim-Version/Health, empfohlene Companions
  (markdown.nvim/color_my_ascii erkannt?).
- **Aufwand:** klein-mittel.

### 8. Log-Command + Log-Features
- **Symptom:** `:MDViewShowWebLogs` zeigt nur Relay-stdout.
- **Fix:** `:MDViewLog` (oder Ausbau) das **den internen Ring** (`mdview.log`
  Snapshot) + Relay-stdout + `[client]`-Zeilen zusammen zeigt; Level-Filter,
  Tag-Filter, „nach Datei exportieren" (`:MDViewLog export <path>`). Nutzt die
  bereits vorhandene `lib.nvim.logger`-Infra.
- **Aufwand:** mittel.

---

## P2 — größer / optional

### 9. Fokus nach Öffnen im nvim behalten (konfigurierbar)
- **Wunsch:** default-Browser-Tab öffnen, **ohne** dass der Fokus dorthin springt
  (im nvim bleiben); als `browser.focus = "browser" | "nvim"` einstellbar.
- **Realität:** OS-spezifisch, kein plattformübergreifendes API. Windows:
  nach dem Öffnen nvim-/Terminal-Fenster per PowerShell reaktivieren (fragil);
  macOS: AppleScript; Linux: `wmctrl`/`xdotool`. Nur als bewusstes,
  best-effort Opt-in mit klarer „fragil"-Warnung.
- **Aufwand:** hoch (fragil, pro OS). Zurückgestellt bis P0/P1 stehen.

### 10. Companion-Plugins dokumentieren (kein Hard-Dep)
- **markdown.nvim:** dessen Buffer-*Text*-Transforms (TOC, `:Markdown refs`,
  Tabellen, heading-shift, headline_spacing) werden durch mdviews Live-Mirror
  **automatisch** in der Preview reflektiert — **ohne** Integration. → In der
  README als „empfohlener Begleiter" dokumentieren + die Mirror-Architektur
  erklären (jedes text-änderndes nvim-Feature ist gratis in der Preview).
- **color_my_ascii.nvim:** highlightet im nvim-Buffer, **nicht** als HTML →
  nicht spiegelbar. Wert: Sprach-Erkennung + Farbschemata könnten das
  client-seitige Highlighting (P1-5) informieren; als nvim-seitiger Begleiter
  empfehlen (highlightet die Quelle in nvim, mdview highlightet separat im
  Browser). **Kein** Hard-Dep.
- **Aufwand:** klein (Doku) + optionale Soft-Detection.

### 11. Lazy-`cmd`-Liste aktualisieren (kleiner Hinweis)
- Deine lazy-Config listet nur die alten Commands unter `cmd`. Neue Commands
  (`MDViewToggle`, `MDViewTheme`, `MDViewDiagnose`, künftig `MDViewLog`) sollten
  rein, damit Lazy-Loading auch auf sie triggert. Betrifft nur die README-Beispiele.

---

## Architektur-Notiz: „Live-Mirror" als Multiplikator

mdview pusht den **rohen Buffer-Text** live; der Browser rendert neu. Daraus
folgt (deine Intuition, bestätigt):

- **Text-ändernde nvim-Features** (refs-update, TOC, Tabellen-Format, Snippets,
  Suchen/Ersetzen, jedes Plugin das den Buffer editiert) sind **automatisch** in
  der Preview sichtbar — mdview muss sie nicht nachbauen.
- **Nicht** gespiegelt werden **Darstellungs**-Features, die nur nvim-intern sind
  (Treesitter/LSP-Highlight, Extmarks, Conceal, virtuelle Zeilen). Die leben in
  nvims Renderer, nicht im Text → der Browser braucht eigene Lösungen
  (P1-5 Highlighting, eigene Themes).

Konsequenz für Priorisierung: alles, was Darstellung im Browser betrifft
(Highlighting, Themes, Scroll-Präzision), muss **in mdview/Client** gelöst
werden; alles, was den Text betrifft, kommt über Companions „gratis".

---

## Vorgeschlagene Reihenfolge

1. **P0-1** Config-Validierung + Flags freischalten (entsperrt deine Tests)
2. **P0-2** Browser-Close bei `:qa!`
3. **P0-3** click_navigate verifizieren + Backslash-Pfade
4. **P1-7** checkhealth ausbauen · **P1-8** Log-Command (DX, schnell)
5. **P1-4** Cursor-Sync via sourcepos
6. **P1-5 + P1-6** Code-Highlighting + Themes (Design A/B entscheiden)
7. **P2-10** Companion-Doku · **P2-9** Fokus (zuletzt, fragil)

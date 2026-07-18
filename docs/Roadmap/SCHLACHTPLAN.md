# Schlachtplan — Feedback-Runde nach v0.1.0

## Companion-Plugins dokumentieren (kein Hard-Dep)
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

## Lazy-`cmd`-Liste aktualisieren (kleiner Hinweis)
- Deine lazy-Config listet nur die alten Commands unter `cmd`. Neue Commands
  (`MDViewToggle`, `MDViewTheme`, `MDViewDiagnose`, künftig `MDViewLog`) sollten
  rein, damit Lazy-Loading auch auf sie triggert. Betrifft nur die README-Beispiele.

## „nvim-Highlighting spiegeln" (color_my_ascii / Treesitter) — Zukunfts-Feature
- **Befund (tiefer geprüft, `e:\repos\color_my_ascii.nvim`):** Die Färbung liegt in
  `highlighter.lua` / `highlighter_ts.lua` und **wendet** Highlights direkt per
  `nvim_buf_set_extmark` (Keyword-Listen + Treesitter) auf den **Buffer** an — sie
  **gibt keine** `(row, col_start, col_end, hl_group)`-Ranges **zurück**. Die
  Public-API (`.fences`) macht nur Fence-Erkennung.
- **Machbarer Weg (drop JS-Deps, „wie in nvim"):**
  1. color_my_ascii um eine **Export-Funktion** erweitern:
     `tokenize_block(lines, lang) -> { {row, col_start, col_end, hl_group}, … }`
     (die Logik existiert, muss nur „return" statt „set_extmark" liefern) — **oder**
     direkt **Treesitter** in mdview nutzen (allgemeiner, kein Fremd-Plugin nötig).
  2. mdview löst `hl_group -> #hex` via `nvim_get_hl` auf.
  3. Transport: pro Codeblock Spans an den Client senden (neuer ephemerer Kanal,
     an `data-sourcepos` des `<pre>` gekoppelt).
  4. Client wickelt die Spans um den Code — ersetzt hljs/shiki, exakt nvim-Farben.
- **Aufwand:** groß (Injection-Parsing, hl→hex, Transport, Re-Render). Eigenes
  Feature
- Vorteil: mit eignen plugin ohen lsp oder externe plugins können wir desource code in fences in markdown ausreichend gut hiughlighten



---

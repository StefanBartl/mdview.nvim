# Companion plugins (optional)

mdview.nvim is a **live mirror** of your Markdown buffer: it streams the raw
buffer text to the browser, which re-renders it. A useful consequence —

> **Any Neovim plugin that edits the buffer *text* is reflected in the preview
> for free.** You don't implement it in mdview; you just see the result.

- **[markdown.nvim](https://github.com/StefanBartl/markdown.nvim)** — a
  Markdown toolkit (TOC, reference updater, table formatter, heading shifting,
  …). Because those all transform the buffer text, running them updates the
  live preview automatically. Recommended companion, **not** a dependency.
- **[color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim)** —
  highlights fenced code / ASCII art **inside the Neovim buffer**. With
  `browser.highlighter = "nvim"` it also feeds the preview: mdview reads the
  colors back out through color_my_ascii's public API and paints the browser's
  code blocks with them, so both sides show the same thing instead of two
  highlighters guessing the language separately. Blocks color_my_ascii does not
  paint (ASCII art aside, its fence map covers 31 language tags) fall through to
  highlight.js, so nothing loses coverage. Still **not** a dependency: without
  it, `"nvim"` simply has nothing to send and every block falls through. See
  [RENDERING.md](FEATURES/RENDERING.md#nvim--the-buffers-own-colors).

- **[spotlight.nvim](https://github.com/StefanBartl/spotlight.nvim)** —
  color-marks tokens in the buffer (a customer id, an error code in a log
  analysis). mdview mirrors its whole-file spotlights into the preview, in the
  same colors and live: spotlight.nvim announces every change as
  `User SpotlightChanged`, mdview re-reads `require("spotlight").spotlights()`
  and `colors()` and paints the same tokens in the rendered document. On by
  default, a no-op without spotlight.nvim (it is looked up, never required),
  and switchable with `browser.spotlight_sync` / `:MDView spotlight`. See
  [PREVIEW.md](FEATURES/PREVIEW.md#spotlight-mirror).

- **[language.nvim](https://github.com/StefanBartl/language.nvim)** —
  translates Markdown without breaking it (`translate_markdown`: code, link
  targets, front matter and HTML never go to the engine, the result has exactly
  as many lines as the source, in-page anchors follow the translated headings,
  a paragraph seen before comes from a cache). mdview uses it for
  `browser.display_lang` / `:MDView lang`: the buffer stays in its language and
  the preview shows the translation, with `deepl`, `google`, `shell`, `custom`
  or the `ai` engine (through ai.nvim, local models included). It is looked up
  with `pcall(require)` and never loaded otherwise; without it mdview warns once
  and the preview stays original. Nothing is sent to an engine unless
  `display_lang` is set, and the first request names the engine. See
  [PREVIEW.md](FEATURES/PREVIEW.md#display-language-translated-preview) and
  `:checkhealth mdview` (plugin found, engine available, key set).

None is required, and mdview never loads them; `:checkhealth mdview` just
notes when they're present.

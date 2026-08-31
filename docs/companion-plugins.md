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

Neither is required, and mdview never loads them; `:checkhealth mdview` just
notes when they're present.

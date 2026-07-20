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
  highlights fenced code / ASCII art **inside the Neovim buffer**. That's a
  Neovim-side rendering feature (highlight groups, not HTML), so it complements
  rather than feeds the browser preview — mdview does its own client-side code
  highlighting (`browser.highlighter`). Use both to get colored code in the
  editor *and* the browser.

Neither is required, and mdview never loads them; `:checkhealth mdview` just
notes when they're present.

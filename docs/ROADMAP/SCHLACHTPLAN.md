# Battle plan — the feedback round after v0.1.0

## Document the companion plugins (no hard dependency)
- **markdown.nvim:** its buffer *text* transforms (TOC, `:Markdown refs`,
  tables, heading shift, headline_spacing) are reflected in the preview
  **automatically** through mdview's live mirror — **without** any
  integration. → Document it in the README as a "recommended companion" and
  explain the mirror architecture (every text-changing nvim feature is free
  in the preview).
- **color_my_ascii.nvim:** highlights in the nvim buffer, **not** as HTML →
  not mirrorable. Its value: language detection plus colour schemes could
  inform the client-side highlighting (P1-5); recommend it as an nvim-side
  companion (it highlights the source in nvim, mdview highlights separately
  in the browser). **No** hard dependency.
- **Effort:** small (documentation) plus optional soft detection.

## Update the lazy `cmd` list (a small note)
- Your lazy config lists only the old commands under `cmd`. New commands
  (`MDViewToggle`, `MDViewTheme`, `MDViewDiagnose`, and `MDViewLog` in
  future) should go in, so that lazy loading triggers on them too. Affects
  only the README examples.

## "Mirror the nvim highlighting" (color_my_ascii / treesitter) — a future feature
- **Finding (checked more deeply, `e:\repos\color_my_ascii.nvim`):** the
  colouring lives in `highlighter.lua` / `highlighter_ts.lua` and **applies**
  highlights directly to the **buffer** via `nvim_buf_set_extmark` (keyword
  lists plus treesitter) — it does **not return**
  `(row, col_start, col_end, hl_group)` ranges. The public API (`.fences`)
  only does fence detection.
- **A feasible road (drop the JS deps, "the way it looks in nvim"):**
  1. Extend color_my_ascii with an **export function**:
     `tokenize_block(lines, lang) -> { {row, col_start, col_end, hl_group}, … }`
     (the logic exists, it just has to "return" instead of "set_extmark") —
     **or** use **treesitter** in mdview directly (more general, no
     third-party plugin needed).
  2. mdview resolves `hl_group -> #hex` via `nvim_get_hl`.
  3. Transport: send the spans per code block to the client (a new ephemeral
     channel, tied to the `data-sourcepos` of the `<pre>`).
  4. The client wraps the spans around the code — replacing hljs/shiki, with
     exactly the nvim colours.
- **Effort:** large (injection parsing, hl→hex, transport, re-render). A
  feature of its own.
- Advantage: with our own plugin, without an LSP or external plugins, we can
  highlight source code inside markdown fences well enough.



---

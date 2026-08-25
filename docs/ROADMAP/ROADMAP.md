# mdview.nvim — open items

Everything that is pending and concrete enough to be started. What is still
too vague or too exotic for that lives in [`IDEAS/`](IDEAS/).

| Where | What |
| --- | --- |
| **this file** | the **open** items — start here |
| [`DONE.md`](DONE.md) | decision log: what was built and *why that way* |
| [`../FEATURES/`](../FEATURES/) | the catalogue of what exists today |
| [`IDEAS/`](IDEAS/) | ideas with no near-term implementation |
| [`SCHLACHTPLAN.md`](SCHLACHTPLAN.md) | the feedback round after v0.1.0 |
| [`history/`](history/) | pre-rewrite documents, history only |
| [`personal/`](personal/) | personal notes, not part of the roadmap |

---

## `experimental.any_file` — preview for non-markdown files

**Status:** implemented (2026-08-24), **not yet tested in real Neovim** —
please verify by hand before this counts as done.

A first step towards "view.nvim": with `experimental.any_file = true`,
`mdview.config.merge()` widens `ft_pattern` to `{"*"}`;
`helper/previewable.lua` is the actual gate after that (normal buftype,
named, not binary, not mdview's own log buffer — and without `any_file`
additionally `filetype == "markdown"/"md"` as before). The client does not
render a non-markdown file through the WASM renderer, but as a single code
block coloured by file extension. Details: see
[`../FEATURES/FEATURES.md`](../FEATURES/FEATURES.md), the section
"Plain-text preview for non-Markdown files".

Verified so far: the Lua test harness (55 tests, including the new
`previewable_spec.lua`), the client vitest (95 tests), plus a manual browser
check over the relay in standalone `--watch` mode (a `.lua` and a `.txt` file
render correctly highlighted and as plain text respectively). **Not**
verified: the actual path through real Neovim
(`setup({ experimental = { any_file = true } })`, open a file,
`:MDView start`).

**To test:**
- Open a `.lua`/`.py`/similar file, `:MDView start` — does it render
  highlighted in the browser tab?
- Scroll sync (should be proportional, no exact line bar — see the roadmap
  note on scroll-sync parity below/in FEATURES.md).
- `:MDViewBreadcrumbs` on a `.py`/`.sh` file with `#` comments — it should
  not collect fake headings.
- Buffers that are meant to be excluded (terminal, `:help`, quickfix,
  mdview's own log buffer) — they should still be ignored.
- Behaviour with `any_file = false` (the default) — it should behave exactly
  as before (pure markdown mode).

---

## PDF page preview in the link hover

**Status:** open, deliberately deferred (2026-08-17).

The link hover in the browser (`src/client/render/linkHover.ts`) shows only
the file name for `.pdf` targets. The in-editor hover in `markdown.nvim`, by
contrast, renders page 1 inline — `pdfport.render_page` sits in the same
process there.

**Why not in the browser:** the browser cannot ask Neovim directly. The only
return direction is the polling bridge (`lua/mdview/adapter/inbound_poll.lua`,
a 250 ms interval). A PDF hover would therefore need:

1. the browser to place a request in a server queue,
2. up to 250 ms until Neovim polls it,
3. `pdfport.render_page` to rasterize through `pdftoppm` (several hundred ms),
4. the PNG to land in the temp directory — and thereby **not** be deliverable
   over `/asset`, because that route is deliberately confined to the document
   directory.

The result: about a second of latency for a hover, plus a new route that
would have to soften the directory binding — that is, exactly the security
property `/asset` and `/preview` deliberately keep narrow. A bad trade for a
hover.

**The clean road, should it be wanted later:** pre-render at doc-push time
instead of a request at hover time. When Neovim sends a document it knows its
links; it could rasterize referenced PDFs in advance and put the PNGs **next
to the document**. The existing `/asset` path then applies unchanged — no new
route, no softened containment check, no hover latency. Cost: raster work for
PDFs that may never be hovered, and write access next to the document (a
cache directory, cleanup, the `.gitignore` question).

Only tackle this once there is a concrete case for it.

---

## Cooperative tab closing in the `default` browser mode

**Status:** open, medium effort.

In mode `browser.mode = "default"`, mdview opens the URL in the user's normal
browser (their own extensions, their own profile). The price: mdview cannot
close the tab programmatically, so `browser_autoclose` and
`stop_on_browser_exit` are no-ops there.

A possible solution: cooperative closing — the client reacts to a WebSocket
`close` event with `window.close()`. Auto-close would then work in default
mode too, without forcing an isolated profile.

> Origin: noted in [`DONE.md`](DONE.md) (BUGS #2) as "recorded in
> `TASKS.md`" — but that file was never created, so the task was recorded
> nowhere. Added here retroactively.

---

## An external renderer website (opt-in)

**Status:** open, opt-in, with a reservation.

The idea: optionally offload the rendering to an external website instead of
doing it locally via WASM.

**The reservation:** it contradicts the loopback-only model — document
content would leave the device. Only conceivable as an explicit opt-in with a
clear privacy note. `browser.open_url` is already the escape hatch for
opening an arbitrary URL, which covers part of the need.

> Origin: as above — noted in [`DONE.md`](DONE.md)
> (Rendering #2) as "recorded in `TASKS.md`", without that file ever having
> existed.

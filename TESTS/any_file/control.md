# Control document

This file is the **negative control** for the `experimental.any_file`
checklist in `TESTS/CHECK.md`. It is ordinary Markdown, so it must keep going
through the Markdown WASM renderer and keep its per-line `sourcepos` — exact
scroll sync and the cursor line bar included — whether `any_file` is on or
off.

## Second heading

If a run with `any_file = true` changes anything about *this* file compared
to a run with `any_file = false`, the widening leaked into the Markdown path
and case 5 has failed.

### Third heading

Some padding so the document scrolls.

- item 01
- item 02
- item 03
- item 04
- item 05
- item 06
- item 07
- item 08
- item 09
- item 10

```lua
-- A fenced block, to confirm the Markdown renderer is still the one running:
-- under the code view of case 1 there are no fences, the whole file IS code.
local x = 1
```

## Last heading

End of the control document.

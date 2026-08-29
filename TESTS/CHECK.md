# Manual test tasks (in a real Neovim)
[testlink](.\docs\PoC.md)
1. `browser.behavior`: test with two MD files — `reuse` (one tab follows), `new_tab`, `manual`.
    **Enable the opt-in features one by one** (`setup({ experimental = { … = true } })`)
1. `click_navigate = true` → click a relative link `[x](other.md)` → nvim opens `other.md`, the preview follows.
2. `reverse_scroll = true` → scroll in the browser → the nvim cursor follows (with ~250 ms lag, now `transport.inbound_poll_ms` — **please judge here whether it "feels ok"**, that could not be assessed headless; if it does not, that key is the dial).
3. `webtransport = true` → should fall back to WebSocket transparently (no HTTP/3 backend), the preview works normally.
    **Cross-platform (if possible)**
1. Test `:MDViewStart` once on Linux — the shim should catch the lib.nvim bug; once lib.nvim itself is fixed, the shim can go.

---

## `experimental.any_file` — release check

Built 2026-08-24, verified only through the Lua harness (55 tests), the client
vitest (95 tests) and a browser check over the relay in standalone `--watch`.
None of those go through Neovim's autocmd chain — and that chain is exactly
what this flag changes, so the feature is not shippable until the cases below
pass in a real editor.

**What the flag does**, so the expectations below have a reason:

1. `mdview.config.merge` sets `ft_pattern = { "*" }`, so every preview-driving
   autocmd now fires for *every* named buffer, not just `*.md`.
2. `mdview.helper.previewable.is()` becomes the gate that keeps the rest out —
   `buftype ~= ""` (terminal, help, quickfix, nofile/scratch, prompt),
   nameless buffers, `log_buffer_name` (`mdview://logs`), binary buffers.
   Before this flag that exclusion was an accidental side effect of the
   Markdown-only `ft_pattern`; now it is explicit logic, and therefore
   something that can have a hole in it.
3. The client renders non-Markdown as a syntax-highlighted read-only code view
   (extension -> language, `src/client/highlight/languageForPath.ts`) instead
   of through the Markdown WASM renderer. Scroll-sync falls back to
   proportional — no per-line sourcepos, so no cursor line bar.

Config for the whole run:

```lua
require("mdview").setup({ experimental = { any_file = true } })
```

Fixtures: `TESTS/any_file/` — `sample.lua`, `sample.py`, `sample.sh`,
`control.md`. All four are taller than one screen so scrolling has room.

### 1. Open and render

`:e TESTS/any_file/sample.lua` -> `:MDView start`. Repeat with `sample.py`.

- **Expected**: a browser tab opens and shows the file as highlighted code —
  Lua keywords coloured, comments dimmed, no Markdown structure imposed.
- **Fails as**: no highlighting at all (extension missing from
  `languageForPath.ts`), or the Markdown renderer ran anyway — `#` comments
  turn into H1 headings, indented lines into code blocks, the file reads as
  scrambled prose.
- **Note down**: which of the two, and for which extension.

### 2. Scroll sync

With `sample.lua` previewed, scroll to the middle of the buffer, then to the
end.

- **Expected**: the browser follows *proportionally* — halfway down the buffer
  puts the page roughly halfway down. No exact line match, and **no cursor
  line bar** (there is no per-line sourcepos for code).
- **Fails as**: the page does not move at all, or it jumps to the top / a
  wrong offset because something still expects sourcepos.
- **Note down**: whether the proportional lag "feels ok" — same judgement call
  as `reverse_scroll` above, it cannot be assessed headless.

### 3. Breadcrumbs on `#`-comment languages

`:e TESTS/any_file/sample.py`, move the cursor through the file (the
heading-shaped comments around `# Setup` / `# ## Helper functions` are the
trap), then `:MDView breadcrumbs`. Repeat with `sample.sh`.

- **Expected**: every entry for these files reads `(top)`. `core/breadcrumbs.lua`
  only scans for ATX headings when the filetype is `markdown`/`md`; in Python
  and Shell `#` is a comment marker.
- **Fails as**: the comment lines appear as outline entries — the filetype gate
  did not hold (e.g. `filetype` was still empty when the autocmd fired).
- **Then also**: `:MDView breadcrumbs export` and check the written file shows
  the same thing.

### 4. The exclusions

With the preview running on `sample.lua`, open each of these and watch whether
the preview switches to it:

- `:terminal`
- `:help autocmd`
- `:copen` (fill it first, e.g. `:vimgrep /line/ TESTS/any_file/sample.lua`)
- `:MDView log` (mdview's own log buffer, `mdview://logs`)

- **Expected**: none of them triggers a push; the preview keeps showing
  `sample.lua`.
- **Fails as**: the preview switches to the terminal or the quickfix contents.
  The log buffer is the worst case — previewing it writes to the log, which
  pushes again, which writes again.
- **Why this case exists at all**: with `ft_pattern = { "*" }` the autocmds now
  *do* fire for these buffers. Only `previewable.is()` stops them.

### 5. Regression with the flag off

Restart Neovim with `experimental = { any_file = false }` (or the key omitted).

- **Expected**: `control.md` previews exactly as it did before this feature —
  Markdown renderer, exact scroll sync, cursor line bar. On `sample.lua` the
  *live* path stays silent: `ft_pattern` is back to `*.md`/`*.markdown`/`*.mdx`,
  so edits in it never reach the browser and switching to it does not change
  what the preview shows. (`:MDView start` itself does not gate on filetype —
  it pushes whatever buffer is current — so the interesting observation is what
  happens *after* that first push, not the push itself. Note down what you see
  either way; this is the one expectation here that was reasoned from the code
  rather than measured.)
- **Fails as**: anything at all differs on the Markdown path. `previewable.is()`
  sits in the *shared* path, so a bug there breaks the default too — an
  experimental flag that misbehaves while switched off.

### Verdict

- All five pass -> drop `experimental` from the key, document it as supported.
- Case 1 or 2 fails -> client-side, `languageForPath.ts` / the scroll bridge.
- Case 3 or 4 fails -> `helper/previewable.lua` or `core/breadcrumbs.lua`.
- Case 5 fails -> `config/init.lua`'s `ft_pattern` override leaked.

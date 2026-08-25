# Concept: link handling + cursor overlay in the browser

> Two feature concepts (no implementation yet). Each one: problem → current state →
> concept with stages/options → transport/implementation sketch → recommendation.

---

## Feature 1 — link behaviour in the preview tab

### Problem
Clicking an **external** link (`http…`) in the preview navigates the browser away
**in the same tab** → the mdview tab is "gone" and the WebSocket connection is
dead. A further question: what happens in principle when you navigate away from
the "markdown document" in the tab — does mdview close, does it stay "cached", …?

### Current state
- **Relative links** (`other.md`, `./x.md`) → `click_navigate` (now on by default)
  intercepts the click, opens the file in nvim, and the preview follows. **No**
  navigating away. ✔
- **External links / `mailto:` / absolute `/…` / protocol-relative `//…`** →
  `navTargetFromHref` returns `null` → **not** intercepted → the browser follows in
  the same tab. ✘ (Ammonia does set `rel="noopener noreferrer"`, but **no**
  `target`.)
- **In-page anchors** (`#heading`) → standard browser scrolling in the tab. ✔ (no
  problem)
- **Relay lifecycle:** the relay hangs off nvim's `:MDViewStart`/`:MDViewStop`,
  **not** off the tab. If the tab navigates away or is closed, the relay keeps
  running; the content is "held" (LastPayload) as long as the session lives.

### Concept
1. **External links → new tab** (the core fix):
   after every render (as with the highlighting) give every "non-navigable" `<a>`
   (the ones `navTargetFromHref` classifies as external)
   `target="_blank" rel="noopener noreferrer"`. Result: an external link opens in a
   **new** tab and the mdview tab survives. Alternatively intercept the click +
   `window.open(href, '_blank', 'noopener')` — but the `target` attribute is
   simpler and more robust (it also works for middle-click/ctrl-click).
2. **In-page anchors** keep the standard behaviour (scrolling in the tab).
3. **Relative md links** stay on `click_navigate`.
4. **Clarify the "navigating away" semantics (docs + a small behaviour):**
   mdview does **not** close on tab navigation. The recommended, "usual"
   behaviour:
   - the relay stays (bound to nvim) → the session keeps living.
   - if you do end up on a foreign page (e.g. manually), you fetch the preview back
     with **`:MDViewOpen`** (opens a fresh tab with the current content from
     LastPayload).
   - optional extension: the client detects the WS `close` and shows a discreet
     overlay "connection lost — `:MDViewOpen` in nvim" instead of a silent, dead
     page. No auto-reconnect needed (the new tab via `:MDViewOpen` is cleaner).

### Options / decisions
- **Default:** external links **always** in a new tab (usual for preview tools).
- **Config:** `browser.external_links = "new_tab" | "same_tab"` (default `new_tab`),
  passed to the client as `&extlinks=`.
- **Security:** `rel="noopener noreferrer"` is already set (no `window.opener`
  leak) — keep it.

### Implementation sketch
- Client `render/externalLinks.ts`: `markExternalLinks(root)` runs after every
  render and sets `target`/`rel` on external `<a>`. It reuses the
  `navTargetFromHref` logic (external = the cases that yield `null`, except `#…`).
- Called in `main.ts` next to `highlight(...)` in `renderMarkdown`.
- jsdom test: an external link gets `target="_blank"`, a relative one or an anchor
  does not.
- **Effort:** small.

---

## Feature 2 — show the cursor position in the browser (overlay)

### The wish
**See in the browser tab where the nvim cursor currently is** — a cursor character
overlaid exactly at the spot you are at in nvim (line/column).

### The core challenge
Source → rendered HTML is **not** 1:1: markdown syntax disappears on rendering
(`**bold**` → `<strong>bold</strong>`, `# ` gone, `[txt](url)` → `txt`). The
**source column** therefore does not match the **rendered column**. We have
`data-sourcepos="startLine:startCol-endLine:endCol"` — but only at **block**
level, not per character.

### Concept — staged by accuracy/effort

**Stage A — line marker (robust, recommended first):**
- nvim sends the cursor line (already arrives via scroll_sync). The client
  highlights the **current block / the current line**:
  - variant A1: a discreet line background or a left margin bar on the target
    element (like "current line" in editors).
  - variant A2: a caret bar at the **start** of the line in the target block (for
    multi-line blocks positioned via interpolation as with the scrolling).
- No column problem, immediately useful ("you are here").

**Stage B — character-approximate caret (extension, opt-in):**
- nvim additionally sends the **column**. The client:
  1. finds the target block via sourcepos (as in stage A).
  2. sets a point inside the block with the **DOM `Range` API**: walk the text
     nodes until ~`col` rendered characters are reached (best-effort — removed
     syntax is ignored), `range.getBoundingClientRect()` yields (x,y) → insert an
     absolutely positioned, blinking caret overlay there
     (`<span class="mdview-caret">`).
- Inaccurate with a lot of inline markup in the line, but usually usable for prose.
  Communicate clearly as "approximate".

**Stage C — exact source mapping (large, later):**
- Ship a real source map with the render (WASM gives each inline node its source
  range), and the client maps (line, column) exactly onto a DOM position.
  Expensive (comrak's inline sourcepos is limited; possibly a custom renderer
  hook). Probably overkill for a preview — only on genuine demand.

### Transport
- Extend `scroll_sync` (resp. a cursor channel): today's `line/total/viewfrac` →
  `line/total/viewfrac/col`. Update on every `CursorMoved`/`CursorMovedI`
  (throttled, as now). Ephemeral (no LastPayload).
- **Interaction:** the cursor marker is **independent** of the scroll mode. With
  `scroll_sync_mode="cursor"` (mirror) the marker automatically sits where nvim
  shows it too — they go together well.

### Presentation
- An overlay element in the `#mdview-root` container, `position: absolute`, with a
  blinking CSS animation. Colour from the theme (`--md-fg` or a new
  `--cursor-color`).
- Reposition on resize / re-render (update the marker after every render and every
  cursor ping).
- Config: `browser.cursor_marker = "off" | "line" | "caret"` (default `off` or
  `line` — to be decided), passed to the client as `&cursor=`.

### Recommendation
1. **Stage A (line marker)** first — robust, little effort, no column problem.
2. **Stage B (approximate caret)** as an opt-in extension.
3. Defer stage C.

---

## Prioritisation / order (proposal)
1. **F1** external links → new tab (small, fixes a real "tab gone" bug).
2. **F1** disconnect overlay + docs "the relay stays, `:MDViewOpen` fetches it back".
3. **F2 stage A** line marker.
4. **F2 stage B** approximate caret (opt-in).
5. F2 stage C only on demand.

## Open decisions for you
- F1: offer the `browser.external_links` config at all, or **always** open external
  links in a new tab (fixed)?
- F2: default for `cursor_marker` — `off`, `line` or `caret` right away?
- F2: is stage A/B (approximate) enough for you, or do you eventually want stage C
  (exact) — that is considerably bigger.

---

## Status / implementation (2026-07)

Implemented in v0.2.0 (feature commits):

- **F1 external links → new tab.** `src/client/render/externalLinks.ts`
  (`markExternalLinks`) sets `target=_blank rel=noopener noreferrer` on external
  `<a>`. Configurable via `browser.external_links` (`"new_tab"` default |
  `"same_tab"`), passed to the client as `&extlinks=`. The decision on "always
  fixed vs. configurable": **configurable**, default `new_tab`.
- **F1 back/forward.** `src/client/render/history.ts`: Neovim sends a `\x04` doc
  ping per document change (`/doc` endpoint → `ws_client.send_doc`), the client
  performs a `pushState`; `popstate` asks Neovim via `/nav` to open the target
  document again (needs `experimental.click_navigate`, on by default). The
  `viaPopstate` flag prevents push loops.
- **F2 stage A (line marker).** `src/client/render/cursorMarker.ts`
  (`updateCursorMarker`), a blinking bar in the left gutter at the cursor line,
  positioned with the same sourcepos block + in-block interpolation as the scroll
  sync. Configurable via `browser.cursor_marker` (`"line"` default | `"off"`),
  passed to the client as `&cursor=`. Decision on the default: **`line`** — "what
  works well and is simple".

- **F2 stage C (exact column caret via a source map).** DONE — see below.

### Stage C — exact column caret via a source map (implemented)

Implemented as `browser.cursor_marker = "caret"`. The route we previously
described as "expensive" turned out to be considerably cheaper than feared in one
respect: comrak (0.29) **already** carries reliable inline source positions on the
AST nodes (via `parse_document` with `render.sourcepos = true`), and those columns
are **byte-based** — exactly the unit in which Neovim delivers its cursor column
(`nvim_win_get_cursor()[2]`, 0-based). That removes the feared byte/char
conversion between source and editor; only a byte→UTF-16 conversion in the client
for the DOM `Range` remains.

Building blocks:
- **Renderer** (`native/wasm-render/src/lib.rs`): `render_markdown(input, source_map)`.
  With `source_map = true` an AST walk runs (`annotate_source_positions`) that
  wraps every inline `Text` and `Code` node in `<span data-sp="sl:sc:el:ec">…</span>`
  (in place as an `HtmlInline`, no arena allocation). Excluded: nodes under `Image`
  (whose text ends up in the `alt` attribute) and code blocks (the client
  highlighter re-tokenises those). ammonia lets `span` + `data-sp` through. Rust
  tests cover byte columns, multibyte, inline code, `alt` protection and XSS.
- **Transport**: the scroll ping now carries the cursor column in the 4th field
  (`line/total/viewfrac/col`), `col` = the 0-based byte column.
- **Client** (`src/client/render/cursorMarker.ts`): finds the `data-sp` run that
  contains the column, converts byte→UTF-16, finds the text node + offset and
  measures the caret's pixel position via a **single-character box** (not via a
  collapsed `Range` — its `getBoundingClientRect` yields a degenerate box in
  several engines; verified in a browser probe). It falls back to the line marker
  when no run covers the position (an empty line, a code block).

Limits (deliberately accepted): within a run containing escapes/entities (`\*`,
`&amp;`) source bytes and rendered characters drift apart; the caret can be off by
a few characters there. Runs are short, so the deviation stays small.

The marker-consensus heuristic the user proposed (the n-th `a`, counting
whitespace …) was not needed — the real source map solves this directly and
exactly.

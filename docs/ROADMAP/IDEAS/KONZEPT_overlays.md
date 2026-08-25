# Concept: an overlay system for the preview

> A concept, not implemented yet. Goal: control **arbitrary, switchable overlays**
> over the browser preview from Neovim — a floating TOC, a cursor magnifier,
> keycast and others — as **one generic, extensible system**, not as loose
> individual features. It builds on the existing live control channel
> (`\x05` `/control` → `adapter/control.lua` → client `applyControl`), with which
> `:MDViewCursor`/`:MDViewZoom`/`:MDViewReveal` already change the open tab today
> without a reload.

---

## 1. Basic principle

An **overlay** is an independent, switchable UI layer over the rendered document.
It only draws, it does not touch the content, and several overlays can be active at
once. It is toggled live from nvim.

In fact overlays already exist: `cursor_marker` (line/caret/section), the
`⇅ scroll enabled` badge, `zoom`. The concept **generalises** that into a manager
with a registry, so that new overlays are cheap to add and do not get in each
other's way (a shared layer + z-index ordering).

---

## 2. Architecture

### 2.1 Client — overlay manager + registry

A shared overlay level in the DOM:

```
#mdview-overlays   position: fixed; inset: 0; pointer-events: none; z-index: 20
  └─ one container per overlay; individual overlays opt back in via
     pointer-events:auto (a clickable TOC etc.)
```

An overlay implements a slim interface:

```ts
interface Overlay {
  name: string;
  mount(ctx: OverlayCtx): void;     // create DOM, set listeners
  unmount(): void;                  // remove everything again
  onCursor?(line: number, col: number): void;  // per scroll/cursor ping
  onRender?(): void;                // after every re-render (innerHTML wiped)
  onControl?(data: unknown): void;  // overlay-specific control payload
}

interface OverlayCtx {
  root: HTMLElement;          // #mdview-root (the content)
  layer: HTMLElement;         // #mdview-overlays (the overlay level)
  headings(): HeadingInfo[];  // from the DOM (h1..h6 + data-sourcepos)
  caretPixel(line, col): {x,y,h} | null; // reused from cursorMarker
  governingHeading(line): HeadingInfo | null; // from the section-spotlight logic
}
```

The **manager** holds the active overlays, calls the hooks (`onCursor` on the
scroll ping, `onRender` after every `renderMarkdown`, `onControl` on
overlay-addressed control messages) and mounts/unmounts on a toggle. The helpers in
`OverlayCtx` bundle what several overlays need — above all the already existing
caret pixel computation (`caretPixelBox`) and the "governing heading" logic from the
section spotlight, so that the TOC & co. reuse them instead of duplicating them.

### 2.2 Transport

- **Toggles & low-frequency updates** go over the existing control channel:
  `{overlay: {name, on}}`, batchable as `{overlays: {toc:true, keycast:false}}`.
  `applyControl` passes that on to the manager.
- **High-frequency data streams** (keycast!) get **their own ephemeral channel**
  analogous to `/scroll` (`\x01`): a new `/keys` endpoint with the prefix `\x06`,
  batched/debounced on the nvim side — not one HTTP POST per keystroke. Overlays
  that are only toggled do not need this.
- **The initial state** on open via the URL param `&overlays=toc,keycast`, so that a
  reopened tab (`:MDViewOpen`) restores the active overlays — the same pattern as
  `?cursor=` / `?zoom=`.

### 2.3 Neovim

- **One generic command**: `:MDViewOverlay <name> [on|off|toggle]` plus
  `:MDViewOverlay list` (shows registered overlays + their state). Tab completion
  over the names. (Optionally thin aliases `:MDViewTOC`, `:MDViewKeycast`.)
- **Config**: `browser.overlays = { toc=false, magnifier=false, keycast=false }` as
  the default + a memo for reopening.
- **Keymaps**: mdview ships none, but the docs give examples — the wish was, after
  all, "toggle quickly":
  ```lua
  map("n", "<leader>ot", "<cmd>MDViewOverlay toc toggle<cr>")
  map("n", "<leader>om", "<cmd>MDViewOverlay magnifier toggle<cr>")
  map("n", "<leader>ok", "<cmd>MDViewOverlay keycast toggle<cr>")
  ```
- **A data-source manifest** in Lua: per overlay, which nvim side it needs. That way
  keycast registers `vim.on_key()` **only** while it is active and detaches it again
  when switched off (no permanent cost).

### 2.4 Lifecycle & persistence

Overlays are purely preview-side and toggled live. `browser.overlays` is the default
+ the reopen memo. **Keycast defaults to off** (privacy, see below).

---

## 3. The concrete overlays

### 3.1 Floating TOC (mini outline)  — small–medium

- **Data source**: purely client-side from the DOM (`h1..h6` + `data-sourcepos`).
  No new nvim side needed.
- **UI**: a floating panel in a corner; a list of the headings indented by level;
  the **current section highlighted** — it uses the cursor line (already arriving
  via the scroll ping) + the same "governing heading" logic as the section
  spotlight. Plus a progress indicator ("section 3/12" or a thin bar), so the
  viewer sees where in the document you are.
- **Interaction**: clicking an entry scrolls the preview there. Optionally (decision
  below): drag the nvim cursor along (via the existing reverse-scroll bridge
  mechanism).
- **Why first**: the highest benefit for the coaching case, and it builds almost
  entirely on what exists.

### 3.2 Cursor magnifier  — medium

- **Data source**: the caret pixel position (already available via `caretPixelBox`;
  exact with the `source_map` spans, coarse via the block position without them).
- **UI (a real lens)**: a round `position:fixed` lens with a **cloned, scaled**
  cut-out of `#mdview-root` — the text stays vector-sharp (no pixel sampling à la
  html2canvas). Reposition on the cursor ping, synchronise the clone's `innerHTML`
  on a re-render.
- **UI (the simpler "focus zoom" variant)**: instead of a lens, gently enlarge the
  block/paragraph under the cursor (fisheye-light). Less code, good for "look right
  here".
- **Recommendation**: focus zoom as v1, the real lens as an extension.

### 3.3 Keycast (showing keyboard input)  — medium

- **Data source**: `vim.on_key()` in nvim → a ring buffer of the last N keys,
  **debounced** (~120 ms) → POST `/keys` → a `\x06` broadcast to the client.
- **UI**: a transient pill at the bottom (like *screenkey*), showing the most
  recently pressed keys and fading out after ~1.5 s.
- **Translation**: raw bytes → readable names (`j`, `<C-w>`, `<Esc>`, `:w<CR>`) via
  `vim.fn.keytrans()` — on the nvim side, the client only displays.
- **Privacy** (important): insert-mode keys would show the typed text. A config
  `keycast_scope = "non_insert" | "all"` (default `non_insert`: only
  normal/command/operator keys) and keycast **entirely off by default**. That way
  the viewer sees the *operation* (motions, commands), not necessarily every letter.

### 3.4 Further ideas (worth thinking through now)

- **A reading progress bar**: a thin bar at the top, the position in the document.
- **An attention ping / "laser pointer"**: `:MDViewPing` triggers a short highlight
  pulse at the caret — directing the gaze without a mouse. (A tiny overlay, a large
  effect on calls.)
- **Presenter notes**: `speaker` fences (analogous to `private`) that appear **only**
  as an nvim-side overlay/panel, not in the shared tab — bullet points for you,
  invisible to the viewer. (Bigger; worth its own concept.)
- **A minimap** of the document at the edge.

---

## 4. Relationship to the existing features

`cursor_marker`, the rscroll badge and `zoom` are already overlays in effect.
Proposal: **new** overlays run through the manager; the existing markers stay as
they are for now and are **optionally** pulled under the overlay umbrella **later**
(a pure refactor, not a must). The only hard point now: introduce a shared overlay
level + a clear z-index ordering, so that TOC / lens / keycast / marker stack
cleanly instead of overlapping chaotically.

---

## 5. Phases

1. **Foundation**: overlay manager + registry + the `#mdview-overlays` level +
   `:MDViewOverlay` + `browser.overlays` + control/URL routing.
2. **The floating TOC** (uses the section logic + headings).
3. **Focus zoom / lens**.
4. **Keycast** (a new `/keys` channel + `vim.on_key` + `keytrans`).
5. **Extras**: progress bar, attention ping.

Every phase is independently runnable and testable (the manager + per overlay:
vitest/jsdom for the client logic, headless nvim for the command/data source, a
browser probe for pixel positions — as with the caret and the section).

---

## 6. Open decisions for you

- **Command form**: one generic `:MDViewOverlay <name> [on|off|toggle]` (+ `list`) —
  the recommendation — or one command per overlay? (Both work; generic + optional
  aliases is the most flexible.)
- **TOC click**: scroll only the preview, or drag the nvim cursor along too?
- **Keycast**: default scope `non_insert` vs. `all`, and whether it can be offered
  by default at all (it stays opt-in in any case).
- **Lens**: the pragmatic focus zoom first, or the real clone lens right away?
- **Migration**: should `cursor_marker`/badge/`zoom` eventually move under the
  overlay manager, or stay separate permanently?

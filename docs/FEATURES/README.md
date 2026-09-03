# mdview.nvim — what exists

The complete catalogue: **everything that is implemented**, not only what a
user operates directly. The machinery underneath — caches, throttling, the
diff transport, lifecycle — is here on equal footing, because working on this
plugin needs that answered just as often as "which command does that".

| Where | What |
| --- | --- |
| **this file** | the full overview, user- *and* developer-facing |
| [`PREVIEW.md`](PREVIEW.md) · [`RENDERING.md`](RENDERING.md) · [`OPERATIONS.md`](OPERATIONS.md) · [`SECURITY.md`](SECURITY.md) | the big topics in detail, in the [`FEATURES_FORMAT`](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/FEATURES_FORMAT.md) schema |
| [`MACHINERY.md`](MACHINERY.md) | everything with no command of its own — caches, throttling, the diff transport, lifecycle |

---

## Architecture in one paragraph

Four languages, clean cuts. **Lua** drives (commands, autocommands, process
lifecycle), a **Go** relay distributes (HTTP endpoints plus
WebSocket/WebTransport fan-out, and knows about neither files nor buffers), a
**Rust/WASM** module renders (Markdown to sanitized HTML, in the browser), and
**TypeScript** wires up the tab. Details in
[`../architecture.md`](../architecture.md).

---

## Preview and synchronisation

In detail in [`PREVIEW.md`](PREVIEW.md).

- **Live preview in the browser** — buffer text flows through the relay into a
  browser tab and is rendered client-side.
- **Live push on change and on save** — `TextChanged`/`TextChangedI` plus
  `BufWritePost`.
- **Scroll sync Neovim → browser**, and **reverse scroll** browser → Neovim.
- **Cursor marker** — Neovim's position, shown in the rendered document.
- **Visual selection mirror** — what you select with `v`/`V`/`CTRL-V` is
  highlighted in the preview, for showing a document to other people. Off
  while you edit; `:MDView selection` toggles it.
- **Document pinning** — `:MDView pin` holds the preview on one document while
  you read around in other buffers, instead of the tab following every buffer
  switch.
- **Zoom**, **pause/resume** of the scroll sync, **overlays** (a floating TOC),
  **breadcrumbs** (the session outline).
- **Click to navigate** — clicking a relative link opens the file in Neovim
  instead of navigating the tab away.
- **Link hover preview** — an image, the start of a text file, a parsed URL, an
  anchor's section, or "not found". The counterpart to markdown.nvim's
  in-editor hover.
- **Standalone preview** — runs without (or beyond) the Neovim instance, and
  can be started from a terminal.
- **In-editor preview tab** — `:MDView preview-tab`, with no relay and no
  browser at all.

## Rendering

In detail in [`RENDERING.md`](RENDERING.md).

- **comrak and ammonia in one WASM call** — rendering and sanitization are
  inseparable; no caller can obtain HTML that bypassed the allowlist.
- **Themes**, loaded lazily — a theme is a CSS file plus a map entry.
- **Code-fence highlighting** via highlight.js or Shiki, applied
  asynchronously after insertion into the DOM — or `nvim`, which paints with
  the colors Neovim is already showing and hands what it cannot colour to
  highlight.js.
- **Private blocks** — a fence with the info string `private` renders blurred,
  revealed by a click or by `:MDView reveal`.
- **Local images** — relative `<img src>` is rewritten onto the `/asset` route.
- **Blank-line handling** — blank-line gaps as their own spacers.

## Operating and diagnosing

In detail in [`OPERATIONS.md`](OPERATIONS.md).

- **Installation without a toolchain** — prebuilt artifacts from GitHub
  Releases.
- **`:checkhealth mdview`**, **`:MDView diagnose`** (full report),
  **`:MDView log`** (plugin log), **`:MDView file-log`** (persistent relay
  log), **`:MDView weblogs`** (relay stdout).
- **`lib.nvim` as a hard runtime dependency** — deliberately, rather than a
  tangle of pcall fallbacks.

## Security

In detail in [`SECURITY.md`](SECURITY.md).

- **Loopback-only relay**, with a per-session token and an origin check.
- **Race-free port selection.**
- **WebTransport certificate pinning.**
- **`/asset` and `/preview`** — both bound to the document directory, with a
  traversal check and their own extension allowlist each. `/preview` is the
  stricter of the two, because it returns file *content* rather than bytes the
  browser renders as an image.

---

> **Only theme files live in this folder.** The Features tab's parser reads
> every `##` here as a feature, so the section summaries above — which group
> features rather than being ones — belong in this intro rather than in a theme
> file. As headings in a theme file they were counted as features that do not
> exist.

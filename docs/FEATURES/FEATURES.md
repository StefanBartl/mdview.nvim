# mdview.nvim — what exists

The complete catalogue: **everything that is implemented**, not only what a
user operates directly. The machinery underneath — caches, throttling, the
diff transport, lifecycle — is here on equal footing, because working on this
plugin needs that answered just as often as "which command does that".

| Where | What |
| --- | --- |
| **this file** | the full overview, user- *and* developer-facing |
| [`PREVIEW.md`](PREVIEW.md) · [`RENDERING.md`](RENDERING.md) · [`OPERATIONS.md`](OPERATIONS.md) · [`SECURITY.md`](SECURITY.md) | the big topics in detail, in the [`FEATURES_FORMAT`](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/FEATURES_FORMAT.md) schema |
| [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md) | *why* something was built the way it was (decision log) |
| [`../ROADMAP/ROADMAP.md`](../ROADMAP/ROADMAP.md) | what is still open |

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
- **Code-fence highlighting** via Shiki (with an hljs path), applied
  asynchronously after insertion into the DOM.
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

# For developers

From here on: machinery that has no command of its own but affects every
change.

## The readiness cache in `ws_client`

`live_push` wraps **every** `TextChanged` in a `wait_ready`. Without a cache
that would mean one `curl /health` per keystroke. `M._ready` remembers a server
once it has been seen healthy; `M.reset_ready()` drops that on stop/respawn.

- **Module:** `lua/mdview/adapter/ws_client.lua` (`wait_ready`, `reset_ready`, `_ready`)
- **Why:** see [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md), BUGS #5 — the missing
  `cb(true)` is what made the need for a cache visible in the first place.

## Trailing throttle for live pushes

Every push starts a `curl` process. Fast edits collapse into **one trailing**
push rather than one per keystroke.

Important, and easy to get wrong: unlike the scroll-sync throttle, which simply
drops a ping, **nothing may be discarded** here — a swallowed push leaves a
preview permanently out of step with the buffer. So a push inside the throttle
window is *deferred*, not dropped.

- **Module:** `lua/mdview/bindings/autocmds/live_push.lua` (`pending_timer`, `cancel_pending`)
- **Config:** `live_push_throttle_ms`; `BufWritePost` is never throttled.

## Line-diff transport (experimental)

Instead of the whole buffer, a line-edit description can be transmitted. Full
snapshots stay the normal path; the diff path is opt-in.

- **Module:** `lua/mdview/utils/line_diff.lua`, `utils/diff.lua`,
  `utils/diff_granular.lua`; client: `src/client/render/diffDoc.ts`
- **Config:** `experimental.line_diff` (off by default)
- **Careful:** a diff applied to a different base state than the client holds
  renders nonsense — hence the envelope with its resync path.

## Plain-text preview for non-Markdown files (experimental)

With `experimental.any_file`, `mdview.config.merge()` widens `ft_pattern` to
`{"*"}`, so Neovim's glob layer fires for every named buffer.
`helper/previewable.lua` is the actual gate after that (empty buftype, named,
not binary, not mdview's own log buffer); without `experimental.any_file` it
additionally requires `filetype == "markdown"/"md"` as before. The client does
not put a non-Markdown file through the WASM renderer, but renders it as a
single code block coloured by file extension — the same
`<pre><code class="language-x">` shape comrak produces for fences, themed for
free through `_base.css` and highlighted for free by the existing hljs/shiki
dispatcher.

- **Module:** `lua/mdview/helper/previewable.lua`; client:
  `src/client/render/fileKind.ts`, `src/client/highlight/languageForPath.ts`,
  `src/client/render/plainText.ts`
- **Config:** `experimental.any_file` (off by default)
- **Careful:** no `data-sourcepos` for these files — scroll sync falls back to
  the existing proportional estimate (see `main.ts`'s `applyScrollPing`
  fallback), and the cursor line bar does not appear. Line-exact parity with
  Markdown is a possible follow-up.

## The document model in the client

One shared model instead of three separate parsers: top-level blocks carrying
`data-sourcepos` (comrak's source map), and from those the heading outline and
the line-to-block mapping.

Used by the **TOC overlay**, **scroll sync**, the **cursor marker** and
**link hover** (anchor resolution). It works off `H1`–`H6` tags, **not** off
`id` attributes — the WASM renderer emits none.

- **Module:** `src/client/render/docModel.ts` (`topLevelBlocks`, `headings`, `governingHeading`)

## Transport abstraction

WebSocket and WebTransport behind one interface; the factory picks.
WebSocketStream was evaluated and rejected (small text updates, no throughput
problem) — see [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md) BUGS #3.

- **Module:** `src/client/transport/` (`transport.interface.ts`, `transportFactory.ts`, `websocket.transport.ts`, `webtransport.transport.ts`)

## Per-document rooms in the relay

The relay knows about neither files nor buffers — only "here is text for room
K, fan it out". Several open files therefore cannot contaminate each other.
Live buffers and the standalone file watcher both end up in the same
`Broadcast`.

- **Module:** `native/server/internal/relay/registry.go`, `internal/source/watch.go`

## The polling bridge, browser → Neovim

Neovim has no WebSocket client, and the relay stays a dumb byte forwarder. For
the return direction (click navigation, reverse scroll) Neovim polls the relay
every 250 ms — only the endpoints that are enabled, and the timer runs only
while at least one of them is.

Those 250 ms are why some browser-side features do not make sense (PDF page
rendering in the hover, for instance — see
[`../ROADMAP/ROADMAP.md`](../ROADMAP/ROADMAP.md)).

- **Module:** `lua/mdview/adapter/inbound_poll.lua`; server: `relay/nav.go`, `relay/scrollbox.go`

## Autocommand lifecycle

Autocommands have a real attach/detach lifecycle; user commands do **not** —
they are registered once at `setup()` and never torn down. The reason: a
`:MDViewStop` that deleted its own commands along the way was a real bug.

- **Module:** `lua/mdview/helper/autocmds_registry.lua`, `bindings/autocmds/init.lua`
- **Why:** [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md), BUGS #4

## Session and process state

A running server is reused; token rotation happens only on an actual spawn.
Restarting with a rotated token against an old process otherwise produced
silent 403s (curl exits 0 on HTTP errors).

- **Module:** `lua/mdview/core/session.lua`, `core/state.lua`, `adapter/server_args.lua`
- **Why:** [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md), BUGS #5

## Test layers

Four suites, one per language: `vitest` (client, jsdom), `go test` (relay,
including the security boundaries of `/asset` and `/preview`), `cargo test`
(renderer/sanitizer), and Lua. `npm run test:all` runs the first three.

- **Module:** `TESTS/client/`, `native/server/*_test.go`, `native/wasm-render/src/lib.rs` (`#[cfg(test)]`), `TESTS/lua/`

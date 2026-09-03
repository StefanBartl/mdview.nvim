# Machinery

What has no command of its own but affects every change: caches, throttling,
the diff transport, the document model, lifecycle. This is the theme file for
everything that does not have a page of its own — the four topics listed
beside it in [`README.md`](README.md) do.

## The readiness cache in `ws_client`

`live_push` wraps **every** `TextChanged` in a `wait_ready`. Without a cache
that would mean one `curl /health` per keystroke. `M._ready` remembers a server
once it has been seen healthy; `M.reset_ready()` drops that on stop/respawn.

- **Module:** `lua/mdview/adapter/ws_client.lua` (`wait_ready`, `reset_ready`, `_ready`)
- **Why:** the missing `cb(true)` is what made the need for a cache visible in
  the first place.

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

## Plain-text preview for non-Markdown files

With `any_file`, `mdview.config.merge()` widens `ft_pattern` to
`{"*"}`, so Neovim's glob layer fires for every named buffer.
`helper/previewable.lua` is the actual gate after that (empty buftype, named,
not binary, not mdview's own log buffer); without `any_file` it
additionally requires `filetype == "markdown"/"md"` as before. The client does
not put a non-Markdown file through the WASM renderer, but renders it as a
single code block coloured by file extension — the same
`<pre><code class="language-x">` shape comrak produces for fences, themed for
free through `_base.css` and highlighted for free by the existing hljs/shiki
dispatcher.

- **Module:** `lua/mdview/helper/previewable.lua`; client:
  `src/client/render/fileKind.ts`, `src/client/highlight/languageForPath.ts`,
  `src/client/render/plainText.ts`
- **Config:** `any_file` (off by default; `experimental.any_file` is a
  deprecated alias). Shipped 2026-08-30 after the five-case release check in
  `TESTS/CHECK.md` passed in a real Neovim.
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
problem).

- **Module:** `src/client/transport/` (`transport.interface.ts`, `transportFactory.ts`, `websocket.transport.ts`, `webtransport.transport.ts`)

## Per-document rooms in the relay

The relay knows about neither files nor buffers — only "here is text for room
K, fan it out". Several open files therefore cannot contaminate each other.
Live buffers and the standalone file watcher both end up in the same
`Broadcast`.

- **Module:** `native/server/internal/relay/registry.go`, `internal/source/watch.go`

## Two stored payloads per room

A room remembers its content (`LastPayload`, written by `Broadcast`) and, since
`browser.highlighter = "nvim"`, its fence highlighting (`LastSpans`, written by
`BroadcastSpans`). A joining connection is seeded with both, **content first** —
the client paints spans onto a rendered document, so the other order would find
nothing to paint.

Stored, not ephemeral, and that distinction is the whole point: every other
sidecar channel (`/scroll`, `/doc`, `/control`) carries a passing event that the
next one supersedes, so seeding a late joiner with it would be wrong. Fence
highlighting describes the *current* document, exactly like the content does. A
reloaded tab would otherwise sit there unhighlighted until the next edit
happened to arrive.

- **Module:** `native/server/internal/relay/registry.go` (`Broadcast`,
  `BroadcastSpans`, `LastPayload`, `LastSpans`), `native/server/main.go`
  (`handleSpans`, `handleWS`)

## The polling bridge, browser → Neovim

Neovim has no WebSocket client, and the relay stays a dumb byte forwarder. For
the return direction (click navigation, reverse scroll) Neovim polls the relay
every 250 ms — only the endpoints that are enabled, and the timer runs only
while at least one of them is.

Those 250 ms are why some browser-side features do not make sense (PDF page
rendering in the hover, for instance).

- **Module:** `lua/mdview/adapter/inbound_poll.lua`; server: `relay/nav.go`, `relay/scrollbox.go`

## Autocommand lifecycle

Autocommands have a real attach/detach lifecycle; user commands do **not** —
they are registered once at `setup()` and never torn down. The reason: a
`:MDViewStop` that deleted its own commands along the way was a real bug.

- **Module:** `lua/mdview/helper/autocmds_registry.lua`, `bindings/autocmds/init.lua`

## Session and process state

A running server is reused; token rotation happens only on an actual spawn.
Restarting with a rotated token against an old process otherwise produced
silent 403s (curl exits 0 on HTTP errors).

- **Module:** `lua/mdview/core/session.lua`, `core/state.lua`, `adapter/server_args.lua`

## Test layers

Four suites, one per language: `vitest` (client, jsdom), `go test` (relay,
including the security boundaries of `/asset` and `/preview`), `cargo test`
(renderer/sanitizer), and Lua. `npm run test:all` runs the first three.

- **Module:** `TESTS/client/`, `native/server/*_test.go`, `native/wasm-render/src/lib.rs` (`#[cfg(test)]`), `TESTS/lua/`

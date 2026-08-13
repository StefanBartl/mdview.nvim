# Preview

Getting a Markdown document on screen, and keeping it there in sync with
whatever you're doing to it.

## Live browser preview

`:MDView start [file] [cwd=…]` spawns the relay binary (downloading it on
first use), attaches the plugin's autocommands, and opens a browser tab
against the current buffer (or the given file). `:MDView stop` tears all of
that back down — relay process, autocommands, and (in isolated browser mode)
the tab itself. `:MDView toggle` is a thin start/stop dispatcher, and
`:MDView open` re-opens a tab against an already-running session without
spawning a second relay.

- **Module:** `lua/mdview/bindings/usrcmds/start/`, `lua/mdview/adapter/runner.lua`, `native/server/main.go`
- **Usercmds:** `:MDView start`, `:MDView stop`, `:MDView toggle`, `:MDView open` — see [../BINDINGS.md#user-commands](../BINDINGS.md#user-commands)
- **Config:** `server_port` (default `43219`; the relay picks the next free port if taken)

## Live push on edit and save

`TextChanged`/`TextChangedI` push the full buffer to the relay so the preview
follows every edit, not just saves; `BufWritePost` does the same on save.
Edits are throttled — a push inside `live_push_throttle_ms` is deferred to a
single trailing push rather than dropped or sent per keystroke — but the
save-triggered push is never throttled, so `:w` always reaches the browser
immediately.

- **Module:** `lua/mdview/bindings/autocmds/live_push.lua`
- **Autocmds:** `TextChanged`, `TextChangedI`, `BufWritePost` — see [../BINDINGS.md#autocommands](../BINDINGS.md#autocommands)
- **Config:** `live_push_throttle_ms` (default `150`)

## Scroll sync (Neovim → browser)

`CursorMoved`/`CursorMovedI` send the cursor's line (and total line count) to
the relay, throttled, so the browser scrolls to follow — line-accurate via
comrak's `data-sourcepos` output, not a percentage-of-file estimate. Where the
line lands in the viewport is configurable: glued near the top, or mirroring
the cursor's relative height inside the Neovim window.

- **Module:** `lua/mdview/bindings/autocmds/scroll_sync.lua`, `src/client/render/scrollSync.ts`
- **Autocmds:** `CursorMoved`, `CursorMovedI`
- **Config:** `scroll_sync` (default `true`), `scroll_sync_throttle_ms` (default `150`), `scroll_sync_mode` (`"top"` default, or `"cursor"`), `scroll_sync_top_offset` (default `0.08`)

## Neovim cursor marker

The preview highlights whatever the Neovim cursor is currently on, in one of
three modes: `line` (highlight the whole source line), `caret` (an exact
inline caret, byte-accurate via the renderer's `data-sp` spans — see
[RENDERING.md](RENDERING.md#source-position-mapping)), or `section`
(spotlight the enclosing heading section — the mode `:MDView cursor toggle`
flips on and off, since it's the one most likely to be toggled repeatedly
while presenting). Changing the mode updates the shared config (so the next
browser URL carries `?cursor=`) and, if a session is already running, pushes
a live control update — no reload needed either way.

- **Module:** `lua/mdview/bindings/usrcmds/cursor.lua`, `lua/mdview/adapter/control.lua`
- **Usercmds:** `:MDView cursor [line|caret|section|off|toggle]` (no argument reports the current mode)
- **Config:** `browser.cursor_marker` (default unset — see the command's own report for the effective value)

## Scroll sync pause/resume

`:MDView sync [pause|resume|toggle]` freezes the nvim→browser scroll sync
(and cursor marker) at runtime without tearing down the session — useful for
jumping to a reference spot in the buffer without dragging the viewer along.
No argument reports whether sync is currently paused.

- **Module:** `lua/mdview/bindings/usrcmds/sync.lua`, `lua/mdview/bindings/autocmds/scroll_sync.lua`
- **Usercmds:** `:MDView sync [pause|resume|toggle]`

## Preview zoom

`:MDView zoom [+|-|reset|<factor>]` adjusts the preview's font-size scale at
runtime — handy for a screen share, where the viewer's own downsampling
already costs legibility, without zooming the whole browser window. Accepts
a relative step (`+`/`-`, 0.1 per press, clamped to 50%–300%), `reset` (back
to 100%), or an explicit factor/percentage (`1.5` or `150` both mean 150%).
Persists into the shared config so a reopened tab starts at the same zoom
(`?zoom=`), and pushes a live update to an already-open tab.

- **Module:** `lua/mdview/bindings/usrcmds/zoom.lua`
- **Usercmds:** `:MDView zoom [+|-|reset|<factor>]` (no argument reports the current zoom)
- **Config:** `browser.zoom` (default `1.0`)

## Overlays (floating table of contents)

`:MDView overlay <name> [on|off|toggle]` mounts/unmounts a named overlay on
top of the rendered preview without a reload — currently one overlay ships,
`toc`, a floating outline with the current section highlighted as the
cursor/scroll position moves. `:MDView overlay list` (or a bare `:MDView
overlay`) reports every known overlay and whether it's currently on. The
Neovim-side manifest (`M.known` in the module below) has to stay in sync
with the overlay names the client actually registers
(`src/client/render/overlays/index.ts`) when a new one is added.

- **Module:** `lua/mdview/bindings/usrcmds/overlay.lua`, `src/client/render/overlays/index.ts`
- **Usercmds:** `:MDView overlay <name> [on|off|toggle]`, `:MDView overlay list`
- **Config:** `browser.overlays.<name>` (per-overlay boolean, default off)

## Breadcrumbs (session outline)

A rough Markdown outline of which document and heading section was visited
when, recorded across the whole preview session — a human-facing summary
for writing follow-up notes after a call, distinct from `:MDView log` (the
internal structured log ring covered in [OPERATIONS.md](OPERATIONS.md)).
`:MDView breadcrumbs` opens the outline in a scratch buffer; `export
[path]` writes it to disk (default `stdpath("log")/mdview-breadcrumbs.md`);
`clear` drops everything recorded so far.

- **Module:** `lua/mdview/bindings/usrcmds/breadcrumbs.lua`, `lua/mdview/core/breadcrumbs.lua`
- **Usercmds:** `:MDView breadcrumbs [export [path] | clear]`

## Reverse scroll (browser → Neovim)

The complement of the above, opt-in: scrolling the preview tab moves the
Neovim cursor to match. Implemented by polling the relay's `/scrollback`
mailbox (a single-slot "latest scroll ratio" value, not a queue), so it
follows with a small lag rather than instantly.

- **Module:** `native/server/internal/relay/scrollbox.go`, `/scrollback` route in `native/server/main.go`
- **Config:** `experimental.reverse_scroll` (default `false`)

## Click-to-navigate

Clicking a relative link in the preview doesn't let the browser follow it —
there's no web server behind those paths — it instead sends the href to
Neovim via the relay's `/nav` queue (polled while a session is active), and
Neovim opens the target document, which flows back into the preview through
the normal push path. External links, in-page anchors, and absolute or
protocol-relative paths are left to the browser untouched; modifier-clicks
(open in new tab, etc.) are also left alone.

- **Module:** `src/client/render/clickNav.ts`, `native/server/internal/relay/nav.go`
- **Config:** `experimental.click_navigate` (default `true` — the one `experimental.*` flag on by default)

## Standalone preview (outlives Neovim)

`:MDView standalone [file] [--no-browser]` hands the file to the relay
binary's own `--watch` mode and steps out of the chain entirely: the relay
polls the file on disk (~4×/s) and pushes changes straight to the browser, so
the preview survives `:qa`. The trade-off is everything that requires knowing
where a cursor is — no unsaved-buffer push (it previews the file *as saved*),
no scroll sync, no cursor marker. Runs on `server_port + 100` by default so it
can sit alongside a normal `:MDView start` session. Needs a relay built with
`--watch` support (v0.3.0+); `:MDView standalone` probes the binary first and
refuses to start rather than spawning a process that silently can't do the
job.

- **Module:** `lua/mdview/bindings/usrcmds/standalone.lua`, `native/server/internal/source/watch.go`
- **Usercmds:** `:MDView standalone` — see [standalone.md](../standalone.md)
- **Config:** `standalone.binary_path` (default `nil`, uses the installed binary)

## Terminal-launched standalone preview

`scripts/mdview-bg.sh`/`.ps1` run a throwaway headless Neovim just long enough
to fire `:MDView standalone`, which spawns the relay and detaches it, then
quit — nothing Neovim-related stays resident. Lets a shell alias like
`mdview-bg some.md` work as a general "render this Markdown" command with no
editor in the loop at all.

- **Module:** `scripts/mdview-bg.sh`, `scripts/mdview-bg.ps1`
- **Config:** environment variables `MDVIEW_PATH`, `LIB_NVIM_PATH`, `MDVIEW_STANDALONE_BIN`, `NVIM`

## In-editor preview tab (no browser, no server)

`:MDView preview-tab` renders the buffer as a read-only, Treesitter-highlighted
mirror in its own Neovim tab (falling back to `syntax=markdown` if the parser
isn't installed) — no relay, no WebSocket, no WASM render pipeline at all.
It's a quick structural read, not a full preview: no CSS, no theming, no
rendered tables. Fully decoupled from `:MDView start`/`stop` — it runs its own
`TextChanged`/`TextChangedI`/`BufWritePost` autocommands in a separate augroup
(`MdviewPreviewTabSync`) with its own lifecycle. If `open_preview_tab` is set,
`:MDView start` opens this instead of the browser (the relay/WASM pipeline
still runs in the background, so `:MDView open` can still bring up the
browser later).

- **Module:** `lua/mdview/adapter/preview_tab.lua`, `lua/mdview/bindings/autocmds/preview_tab_sync.lua`
- **Usercmds:** `:MDView preview-tab`
- **Config:** `open_preview_tab` (default `false`)

## Per-document rooms

The relay knows nothing about files or buffers — only "here is text for room
K, fan it out." Broadcasting a document update only reaches browser tabs
joined to that document's key, so multiple open files (or the same file
opened in two tabs) never cross-contaminate each other's preview. Both real
producers of preview content (a live Neovim buffer, or standalone mode's file
watcher) converge on the same `Registry.Broadcast` call — standalone mode is
the same preview machinery with a different producer, not a second
implementation.

- **Module:** `native/server/internal/relay/registry.go`

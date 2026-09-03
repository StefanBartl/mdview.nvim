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

### Forcing a port for one run (2026-08-24)

`:MDView start port=43000` overrides `server_port` for that spawn only —
closing the flag/option audit's entry. The config key exists, but it is the
wrong tool when the reason is a firewall rule or a port-forward that has to
match exactly, on one machine: editing a config everyone else shares to
answer a local constraint.

`port=` rather than `--port`, because `cwd=` is already this command's
convention and one shape for both beats two.

Applied to the live config and restored right after the spawn, since
`adapter/server_args` reads `config.defaults.server_port` at spawn time and
sits several layers down. Restoring is what keeps it a one-run override —
otherwise the next plain `:MDView start` would silently inherit it. Out of
range (1–65535) is refused; with a server already running it is ignored with
a warning, exactly as `cwd=` is.

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

## Visual selection mirror

What you select in Neovim with `v` / `V` / `CTRL-V` is highlighted in the
preview, live, as you drag it. It exists for showing a document to other
people — a lecture, a screen share, a walkthrough of a checklist or README:
pointing at something in Neovim is invisible to an audience looking at the
browser tab, and selecting it says "this part, here" in the window they are
actually watching.

All three visual modes are mirrored, in their own shape: charwise flows from
the start column to the end column across lines, linewise covers whole lines,
blockwise draws the column range on every line it spans. The highlight follows
the selection while it grows (throttled, with a trailing update so the final
position always arrives) and disappears the moment you leave visual mode.

**Off by default**, and meant to be toggled on for as long as you are showing
the document to someone: `:MDView selection` flips it. While you are editing
rather than presenting, every `v`/`V` drag reaching the browser is noise — the
audience would watch you select things you are only operating on, and off costs
nothing. Switching it on prepares the tab right away (the mirror needs the
renderer's source-position spans, so the tab re-renders once — better at the
toggle than in the middle of the first thing you point at); switching it off
clears a highlight that is currently drawn rather than stranding it there.

It is drawn as rectangles over the document, positioned from the renderer's
`data-sp` source-position spans (see
[RENDERING.md](RENDERING.md#source-position-mapping)) — not by wrapping the
selected text in markup, which could not express a selection that crosses
element boundaries. Fenced code blocks carry no inline spans, so their columns
are resolved from the block's own line structure instead; a block that the
Shiki highlighter rebuilt wholesale loses its source positions and is skipped
rather than guessed at.

- **Module:** `lua/mdview/bindings/autocmds/selection_sync.lua`, `src/client/render/selectionMarker.ts`, `src/client/render/sourcePos.ts`
- **Usercmds:** `:MDView selection [on|off|toggle]` (no argument toggles)
- **Config:** `browser.selection_sync` (default `false`), passed to the client as `?sel=1` when on

## Scroll sync pause/resume

`:MDView sync [pause|resume|toggle]` freezes the nvim→browser scroll sync
(and cursor marker) at runtime without tearing down the session — useful for
jumping to a reference spot in the buffer without dragging the viewer along.
No argument reports whether sync is currently paused.

- **Module:** `lua/mdview/bindings/usrcmds/sync.lua`, `lua/mdview/bindings/autocmds/scroll_sync.lua`
- **Usercmds:** `:MDView sync [pause|resume|toggle]`

## Document pinning

`:MDView pin` holds the preview on the document it is currently showing, and
stops it following the active buffer.

Under the default `browser.behavior = "reuse"` there is one preview tab and it
follows you: switch Markdown files in Neovim and the browser switches too.
That is right while writing and wrong while reading. Opening a second file to
check something — a spec, a README, notes — takes the document you were looking
at off the screen, and nothing puts it back but switching to it again. It is
worst in the case the preview exists for: presenting, where the audience is
watching the tab and not your editor.

A pin freezes the tab on one document, and is deliberately asymmetric. Traffic
from **other** buffers that would land in the pinned tab's room is dropped at
the source — the content push, the scroll ping, the selection mirror, and (in
`"new_tab"` behavior) auto-opened tabs. The **pinned document's own** traffic
is untouched: edit it, scroll it, select in it, and the preview follows along
exactly as before. So a pin is a filter on which buffer may drive the tab, not
a pause switch on the session.

The gate is the room the traffic is headed for, not the buffer it came from.
Under `"new_tab"` / `"manual"` every document has [a room of
its own](#per-document-rooms), so a push from another buffer reaches a tab of
its own and takes nothing away from the pinned one — pinning does not block it.
Blocking there would turn a pin into a global mute, which is not what it means.

`:MDView pin off` releases it and immediately catches the tab up with the
buffer you are actually in, rather than leaving it on the released document
until the next buffer switch happens to move it.

A pin is session state, like the room key of the open tab: it is cleared by
`:MDView stop` and by a fresh `:MDView start`, since it held *that* tab on
*that* document and means nothing without it. `:MDView open` is the one thing
that moves a live pin instead of being blocked by it — it re-points the tab at
the current buffer on purpose, so the pin comes along.

- **Module:** `lua/mdview/core/pin.lua`, `lua/mdview/bindings/usrcmds/pin.lua`, `lua/mdview/bindings/autocmds/buffer_switch.lua`
- **Usercmds:** `:MDView pin [on|off|toggle|status]` (no argument toggles)
- **Config:** none — a pin is runtime session state, not a setting; it interacts with `browser.behavior`

## Preview zoom

`:MDView zoom [+|-|reset|<factor>]` adjusts the preview's font-size scale at
runtime — handy for a screen share, where the viewer's own downsampling
already costs legibility, without zooming the whole browser window. Accepts
a relative step (`+`/`-`, 0.1 per press, clamped to 50%–300%), `reset` (back
to 100%), or an explicit factor/percentage (`1.5` or `150` both mean 150%).
Persists into the shared config so a reopened tab starts at the same zoom
(`?zoom=`), and pushes a live update to an already-open tab.

**An out-of-range number is clamped and says so** (2026-08-24). The value was
always clamped — the audit's entry about "no visible clamping/validation"
described where the check sits, not its absence — but `zoom 500` quietly
applied 300%, so what happened differed from what was asked with nothing
said. It now reports the requested value, the allowed range, and what it
used. A non-number is refused, as before.

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

## Task-list checkbox sync

Ticking a GFM task-list checkbox (`- [ ]` / `- [x]`) in the preview writes the
change back to the source, so it persists instead of reverting on the next
re-render. comrak already emits the checkbox with `data-sourcepos` on its list
item, so the client knows the exact source line; on toggle it POSTs
`<line>:<0|1>` to the relay's `/toggle` bridge. How that's applied depends on
who owns the document:

- **Standalone** (`:MDView standalone`, `mdview-server --watch`): the relay owns
  the file, so it flips just that one marker character in place and its watcher
  re-broadcasts — every open tab updates.
- **`:MDView start`**: the buffer may hold unsaved edits the relay must not
  clobber, so the toggle is queued and Neovim drains it (via the same inbound
  poller as click-to-navigate) and edits the buffer itself, then pushes.

Only the one marker character changes — indentation, bullet style (`-`/`*`/`+`),
line ending and the item text are all preserved. A line that no longer holds a
task marker (a re-render racing a rapid edit) is left untouched rather than
corrupted.

- **Module:** `src/client/render/taskToggle.ts`, `native/server/internal/source/toggle.go`, `native/server/internal/relay/toggle.go`, `/toggle` route in `native/server/main.go`; `:MDView start` buffer edit in `lua/mdview/adapter/inbound_poll.lua`
- **Config:** `sync_checkboxes` (default `true`; `false` renders checkboxes read-only and, in start mode, stops the browser→Neovim poll)

## Text field sync

The same idea extended to editable text fields. Writing a raw-HTML field in the
Markdown source with a `name`:

```html
Title: <input type="text" name="title">

<textarea name="notes" rows="4">initial content</textarea>
```

renders it editable; committing an edit (blur / Enter — **not** every keystroke,
so a re-render never yanks the field out from under you while typing) writes the
value back to the source. Because raw HTML carries no `data-sourcepos` (unlike a
GFM task item), the field can't be located by line — instead it's matched by its
`name` attribute: the relay/Neovim scans the source for `name="…"` and rewrites
just that `<input>`'s `value` or that `<textarea>`'s body. The value is
HTML-escaped on the way in, so it round-trips and can't break out of the tag or
inject markup (`</textarea><script>` becomes inert escaped text).

`name` must be unique within the document (it's the anchor). Only double-quoted
`name="…"` is recognized. The sanitizer permits `<input>` `name`/`value`/
`placeholder` and `<textarea>` `name`/`placeholder`/`rows`/`cols` — never
`formaction`, `form`, or any `on*` handler, so a hostile field still can't act.

- **Module:** `src/client/render/fieldSync.ts`, `native/server/internal/source/field.go`, `native/server/internal/relay/field.go`, `/field` route in `native/server/main.go`; `:MDView start` buffer edit in `lua/mdview/adapter/inbound_poll.lua`; sanitizer allowlist in `native/wasm-render/src/lib.rs`
- **Config:** `sync_fields` (default `true`; `false` renders these fields read-only)

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

## Link hover previews

Hover a link in the preview tab and a small popup shows what it points at —
the browser counterpart to markdown.nvim's in-editor hover, so both surfaces
answer the same question the same way.

| Target | Popup shows |
| --- | --- |
| Image | The picture, via the existing `/asset` route |
| Markdown / text (`.md`, `.markdown`, `.mdx`, `.txt`) | Its first lines, via `/preview` |
| PDF | Name only — see below |
| URL | Host, path and decoded query, parsed locally |
| In-page anchor | The target heading and its first paragraphs, read from the rendered DOM |
| Missing target | "target not found" |

Disable it per session by appending `?hover=0` to the preview URL.

**URLs are never fetched.** The popup parses the URL and shows its parts; it
does not request the page. A hover that issued requests would disclose every
link you brush past to its host — the same reasoning as markdown.nvim's
`hover.url.fetch`, which is off by default for exactly this.

**PDFs show a name only.** Rendering a page needs `pdfport.render_page`,
which lives in Neovim, and the browser has no direct channel to it — only
the 250 ms polling bridge. A round trip through it plus rasterization is
about a second, and the resulting PNG lands in a temp directory that
`/asset` deliberately cannot serve. Pre-rendering referenced PDFs at doc-push
time, next to the document, would solve it properly. The in-editor
hover in markdown.nvim does render the page, because there pdfport is in the
same process.

- **Modules:** `src/client/render/linkHover.ts`, `native/server/main.go` (`handlePreview`)
- **Route:** `GET /preview?key=…&path=…&token=…`

### The `/preview` route

Same security model as `/asset`, deliberately: token check, `key` resolving
to a directory recorded by the trusted Neovim process (never client input),
the client-supplied `path` clamped to that directory, and an extension
allowlist. On top of those it caps bytes read (64 KiB) and lines returned
(40), because unlike an image this response is text the client renders.

Its allowlist is **its own, narrower one** rather than a reuse of `/asset`'s:
`/asset` serves bytes a browser renders as a picture, `/preview` hands back
file *contents*. Source files (`.lua`, `.ts`, `.json`, …) are excluded on
purpose, so a bug in the containment check cannot become "the browser tab
can read any code next to the document". Covered by
`native/server/preview_test.go`.

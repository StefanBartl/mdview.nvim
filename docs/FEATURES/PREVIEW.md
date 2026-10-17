# Preview

Getting a Markdown document on screen, and keeping it there in sync with
whatever you're doing to it.

## Two-way sync

The preview is not a mirror: **changes travel in both directions.** The editor
drives the browser, and the browser writes back into the buffer.

- **Neovim → browser:** the text on every change and on save, scroll position,
  the cursor marker, the visual selection, spotlight highlights, fence colors,
  a translated view, and the document you switch to.
- **Browser → Neovim:** [block editing](#block-editing) (click a block, edit its
  source lines), [task-list checkboxes](#task-list-checkbox-sync),
  [text fields](#text-field-sync), and — opt-in — [reverse scroll](#reverse-scroll-browser--neovim)
  and [click-to-navigate](#click-to-navigate).

What makes the write-back safe to leave on:

- **One undo step.** In `:MDView start` the edit replaces only the lines it
  names, so marks, folds and the rest of the undo history stay; `u` takes it
  back. Standalone, the relay rewrites the file instead (atomically where the
  folder allows).
- **Never over newer text.** Every write-back carries the lines as the browser
  rendered them. If the buffer (or the file) holds something else there now, the
  edit is refused, the tab says "Not saved: …", and the buffer's real text is
  pushed back — nothing is silently overwritten.
- **Out of your way while you type.** In Insert mode a change from the browser
  waits until you stop (a key in the last second) and says so; if you merely
  stand in Insert mode it applies at once as its own undo step.
- **In order.** Changes from the browser reach a buffer in the order they were
  made, one queue per buffer.
- **The right document.** With `browser.behavior = "reuse"` one tab follows the
  active buffer; a write-back goes to the document Neovim last put on screen,
  and a tab that is behind is told and asked to try again.

- **Module:** `lua/mdview/adapter/inbound_poll.lua`, `native/server/internal/source/`, `src/client/render/`
- **Config:** `sync_checkboxes` (default on), `sync_fields` (default on), `edit_blocks` (default off; `:MDView edit`), `experimental.reverse_scroll`, `experimental.click_navigate` — see [../configuration.md](../configuration.md)

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
three modes: `line` (a full-width band over the whole source line, every
visual line of it when it wraps; the column does not move it), `caret` (an exact
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

## Cursor paragraph highlight

On top of the cursor marker, the preview can tint the whole block the Neovim
cursor is in, so whoever reads along sees which part of the document is being
worked on. A block is a paragraph (the text up to the next blank line), or a
whole list, table, code block, block quote, heading or the frontmatter table —
each counts as one block, also when it has blank lines inside (a fenced code
block, a loose list). A cursor on a blank line between two blocks highlights
nothing, however many blank lines there are. The mapping uses the rendered
document's `data-sourcepos`, so it matches what the preview shows; raw HTML
blocks carry no source position and are never highlighted.

Off by default: the line band of the cursor marker already shows where the
cursor is, and a second tint the size of a block, moving with every keystroke,
is more noise than help while editing. Switch it on with `:MDView paragraph`
while presenting or reading along on a second screen.

The color is the background of the highlight group `MdviewCursorParagraph`
(links followed), e.g. `vim.api.nvim_set_hl(0, "MdviewCursorParagraph", { bg =
"#2a3350" })`. Without a background on that group the preview uses its theme's
own faint tint, which suits light and dark preview themes alike; a color from
the group is used as is, so pick one that suits the preview theme. The color is
read at `:MDView start`, with every `:MDView paragraph` and, while the
highlight is on, again after every `:colorscheme` or `'background'` change, so
the open tabs follow the new color without a toggle -- every tab, also with
`browser.behavior = "new_tab"` / `"manual"` and whichever buffer is current.

`:colorscheme` runs `:highlight clear`, which also empties a group you defined
once in your config. mdview then keeps the color the group had last, so the tab
does not fall back to the theme's tint; a colorscheme that defines the group
itself replaces it. To pick the color per colorscheme (or to make the group
survive for Neovim itself), define it in a `ColorScheme` autocmd -- mdview reads
the group one tick after the event, so your autocmd always runs first:

```lua
local function paragraph_hl()
  vim.api.nvim_set_hl(0, "MdviewCursorParagraph", { bg = "#2a3350" })
end
paragraph_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = paragraph_hl })
```

To go back to the theme's tint, clear the group (`nvim_set_hl(0,
"MdviewCursorParagraph", {})`) and run `:MDView paragraph on`, which reads the
group as it is and forgets the kept color.

- **Module:** `lua/mdview/core/cursor_paragraph.lua`, `lua/mdview/bindings/usrcmds/paragraph.lua`, `lua/mdview/bindings/autocmds/cursor_paragraph_sync.lua`, `src/client/render/cursorParagraph.ts`
- **Usercmds:** `:MDView paragraph [on|off|toggle]` (no argument toggles)
- **Config:** `browser.cursor_paragraph` (default `false`); rides the scroll-sync ping, so it needs `scroll_sync` on

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

## Spotlight mirror

The highlights you set with [spotlight.nvim](https://github.com/StefanBartl/spotlight.nvim)
show up in the preview too: mark `SYSsystosca` or `400 (Bad Request)` in Neovim
and every occurrence in the rendered document is marked in the browser, in the
same color, within about a second. It exists for the document you share or read
back — a log analysis full of code blocks, a case write-up — where the markers
you made while working would otherwise stay behind in the editor.

What is mirrored is spotlight.nvim's **whole-file** spotlights (`toggle`/`add`,
every occurrence). "This occurrence only" spotlights (`toggle_here`) are pinned
to a buffer position, which the rendered document has no counterpart for, and
are left out.

The search follows Neovim's rules, not the browser's: the text is matched
**literally** (never as a regex) and **case-sensitively** (unless that spotlight
was created with `ignore_case`); a spotlight made from a visual selection matches
any **substring**, one made from a word only **between word boundaries**. It
looks through everything the preview renders as text — paragraphs, headings,
lists, tables, inline `<code>` and `<pre>` blocks, including a token a code
highlighter has split across several `<span>`s — but never across two blocks and
never inside `<script>`, `<style>` or a form field. A spotlight in **line mode**
tints the whole line (inside a `<pre>`) or block around its matches, more softly
than the match itself, which is drawn on top. Where two spotlights overlap, the
higher color slot wins.

Colors come from Neovim, not from the preview's theme: the eight slots
(`Spotlight1..8`) are read from the live highlight groups, so a colorscheme or
`'background'` switch changes them in the browser as well. A **re-render** (every
buffer change) repaints the highlights, as do removing a spotlight, `clear` and
switching spotlight sets.

It is painted with the CSS Custom Highlight API where the browser has it, which
leaves the document's DOM exactly as rendered; elsewhere matches are wrapped in
`<mark class="spotlight spotlight-N">`. At most `browser.spotlight_max_matches`
matches (default 500) are painted per spotlight, so a token that occurs fifty
thousand times in a log cannot make every render slow; a spotlight that hit the
limit is reported in `:MDView weblogs`.

**On by default, and a no-op without spotlight.nvim.** The mirror is independent
of spotlight.nvim's own persistence: a spotlight that is not persisted for the
file is mirrored all the same, because it is on screen. What leaves Neovim is the
spotlight *texts* and colors, to the loopback relay and the preview tabs of this
session — but if a shared screen or a tab left open must not show what you
marked, switch it off: `browser.spotlight_sync = false`, or `:MDView spotlight
off` for the running session (which also removes the highlights already shown).

How it travels: spotlight.nvim fires a coalesced `User SpotlightChanged`;
mdview re-reads `require("spotlight").spotlights()` and `colors()`, debounces,
and POSTs one JSON object — only when it differs from what the relay already
has — to the relay's `/spotlight` route. The relay broadcasts it to every tab
(`\x07`-prefixed) and keeps the latest, so a tab that is opened or reloaded
later is seeded with the current highlights straight away. This needs a relay
v0.4.0 or newer (the default `install.version` pin has it); with an older pin,
point `dev.binary_path`/`dev.web_root` at a local build. A relay that does not
know the route is reported once.

- **Module:** `lua/mdview/bindings/autocmds/spotlight_sync.lua`, `lua/mdview/core/spotlight_mirror.lua`, `lua/mdview/adapter/ws_client.lua` (`send_spotlight`), `native/server/main.go` (`handleSpotlight`), `src/client/render/spotlightMirror.ts`
- **Usercmds:** `:MDView spotlight [on|off|toggle]` (no argument toggles)
- **Config:** `browser.spotlight_sync` (default `true`), `browser.spotlight_max_matches` (default `500`)


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

Which buffer is written is decided by Neovim, not by the request: it is the
document Neovim last pushed into the tab's room (a content push or a buffer
switch records it, and announces it to the tab). That matters under
`browser.behavior = "reuse"`, where one tab follows the active buffer and its
room key stays the path of the first document, and for a tab that was reloaded
and has not been told which document it shows. The tab also names the document
it believes it shows (the `doc` parameter); a request that names another one
than the room holds is dropped (the tab is behind) instead of guessed at, and
only a buffer mdview itself previews is ever written to. A toggle carries the
text of its line, so one that arrives after another write-back moved the lines
does not tick the neighbour. Text-field sync and [block editing](#block-editing)
work the same way.

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
inject markup (`</textarea><script>` becomes inert escaped text). In
`:MDView start` only the lines that differ are replaced in the buffer, so marks,
folds and extmarks on the lines around the field stay where they are.

`name` must be unique within the document (it's the anchor). The tag is read
attribute by attribute: `name` and `value` may be double- or single-quoted, a `>`
inside a quoted value does not end the tag, and `data-name`, `username` or
`data-value` are other attributes. The sanitizer permits `<input>` `name`/`value`/
`placeholder` and `<textarea>` `name`/`placeholder`/`rows`/`cols` — never
`formaction`, `form`, or any `on*` handler, so a hostile field still can't act.

- **Module:** `src/client/render/fieldSync.ts`, `native/server/internal/source/field.go`, `native/server/internal/relay/field.go`, `/field` route in `native/server/main.go`; `:MDView start` buffer edit in `lua/mdview/adapter/inbound_poll.lua`; sanitizer allowlist in `native/wasm-render/src/lib.rs`
- **Config:** `sync_fields` (default `true`; `false` renders these fields read-only)

## Block editing

Click a block in the preview — a heading, paragraph, list item, code block,
table or quote — and it is replaced by a text field holding that block's
**source lines**. Commit with blur or Ctrl+Enter (Enter in a one-line field);
Esc discards. The edit is written back to the source and flows through the normal
push path, so the block comes back rendered from what you wrote.

**One switch for writing:** `:MDView write` turns block editing and the cursor
caret on together (and starts the preview if none runs); `:MDView write` again
turns both off while the preview keeps running. Map it with
`keymaps = { write = "<leader>mw" }` in `setup()` if you like (no default keymap).

**Raw source, not WYSIWYG.** The rendered HTML has lost the Markdown (link
targets, emphasis markers, table alignment), and turning edited HTML back into
Markdown is lossy. The renderer's `data-sourcepos` already says which lines a
block came from, so those lines are what you edit. A heading is a one-line
input with its `#`s, so changing the level is just editing them.

**Stale edits are refused.** The edit carries the lines as they were rendered
(`expected`); the receiving side applies it only while the document still holds
exactly those lines there. Edited in Neovim in between, the preview shows a short
note ("Not saved: …") and Neovim warns, instead of one side overwriting the other.

- **`:MDView start`**: Neovim replaces only that line range of the buffer (marks,
  folds and the rest of the undo history stay), as **one undo step** — `u` takes
  the edit back. The buffer is then modified; save as usual. The buffer is the
  one of the document Neovim last pushed into the tab's room (also under
  `browser.behavior = "reuse"`, where the tab follows the active buffer), and
  only a buffer mdview itself previews is ever edited, never just any loaded one.
  An edit that finds the buffer changed, not modifiable, or the document on
  screen different is refused and the tab says why ("Not saved: …"). While you
  are typing in Insert mode in that buffer (a key in the last second) the edit
  waits, up to about five seconds, and says so; if you merely stand in Insert
  mode it is applied at once, as its own undo step. A CRLF file loaded as `unix`
  (lines ending in `^M`) is edited and keeps its endings.
- **Standalone** (`:MDView standalone`, `mdview-server --watch … --edit`): the relay
  replaces the lines in the file. Everything outside the range stays byte for byte
  (also a file whose lines end differently), the trailing newline is kept, and it
  is written atomically (temp file + rename; on Windows a rename blocked by another
  program is retried for a few tens of milliseconds, comparing the file again each
  time). In a folder that takes no new file it is rewritten in place instead, after
  the same comparison but not atomically. A symbolic link stays a link: the
  file it points at is rewritten. A **hard link** is not preserved: the rename
  gives the edited name a new file, so another name linked to the old one keeps the
  old text, and owner and ACL entries of the old file are not carried over (the
  permission bits are). The relay refuses an edit (403) unless it was
  started with `--edit`, and one that finds the file changed on disk (409).
- Changes from the preview reach a buffer **in the order they were made** (one queue per
  buffer), and any that cannot be applied -- the lines moved, the line is no longer a
  checkbox, the field is gone, the buffer is read-only -- say so ("Not saved: …" in the
  tab, a warning in Neovim) and the tab gets the buffer text back. A tab that is behind
  (its document ping was lost) is told what is shown and asked to try again. Renaming the
  shown buffer (`:file`, `:saveas`) announces the new path to the tab.
- While an editor is open, incoming renders are held back and run when it closes,
  so a push never pulls the field out from under you.
- Not editable: the frontmatter table (it has no source position), private
  blocks (the click is their reveal), a display language / `browser.transform`
  preview (the lines it shows are not the buffer's), and links, checkboxes and
  form fields, which keep their own job.
- Also not editable (nor can its checkboxes be ticked): a document with a lone CR
  line ending (a `\r` in the middle of the text that is no part of a CRLF). The
  renderer counts it as a line break, the relay and Neovim do not, so the block line
  numbers would name other source lines. The click says so; edit such a file in
  Neovim. A CR that ends the text is fine: a CRLF file loaded with `fileformat=unix`
  ends that way.
- `:MDView edit on|off` is remembered by the tab across a reload (per tab and
  session, in `sessionStorage`); a new session starts from `edit_blocks` again.
- A tab that follows the active buffer (`reuse`) renders by the document on screen,
  not by the first one: switching from Markdown to a code file and back changes the
  renderer with the ping that names the document. The relay keeps the latest such
  ping per room and replays it to a tab that joins later, so a reloaded tab knows its
  document too.
- Inside the field Tab indents (nested lists, code); Shift+Tab, Ctrl/Cmd+Enter or a click
  elsewhere leave it and commit. The field grows with its content.
- A checkbox or text field the relay refuses to save is put back (checkbox) and the
  preview says "Not saved: …"; a 403 reads "read-only" only when the file is, otherwise
  "refused". A checkbox line longer than 2048 bytes is ticked without the stale-line check.
- Leaving the window (alt-tab) does not commit half-typed text (an unchanged
  editor is closed, so the preview does not stand still); moving focus elsewhere
  in the page commits. Enter that confirms an IME composition is not a commit.
  A block of one line commits on Enter (Shift+Enter adds a line break); a longer
  one on Ctrl+Enter. The editor is a textarea either way, so pasted lines are
  kept and a paragraph can be split.
- A block that contains a private block (a list item or a quote around a
  ` ```private ` fence) is not editable either: its source lines hold the
  hidden text.
- Not yet: editing with the keyboard alone (a block can only be opened with a
  click), and keeping what you typed when an edit is refused.

**Off by default**, because a click on text would otherwise open an editor.
`:MDView edit [on|off|toggle]` switches it for the running session (an open
editor is closed without sending when switched off); `edit_blocks = true` makes
it the default.

- **Module:** `src/client/render/blockEdit.ts`, `native/server/internal/source/edit.go`, `native/server/internal/relay/edit.go`, `/edit` route in `native/server/main.go`; `:MDView start` buffer edit in `lua/mdview/adapter/inbound_poll.lua` (`handle_edit`); `lua/mdview/bindings/usrcmds/edit.lua`
- **Usercmds:** `:MDView edit [on|off|toggle]`
- **Config:** `edit_blocks` (default `false`), passed to the client as `?edit=1`; standalone: `--edit` on the relay

## Display language (translated preview)

The buffer stays as it is (say, German); the preview shows another language
(say, English). Switch it on in the setup or at runtime:

```lua
require("mdview").setup({ browser = { display_lang = "en" } })
```

```vim
:MDView lang en        " the preview shows English, the buffer is untouched
:MDView lang           " report: language, trigger, engine, translating 3/12 ...
:MDView lang refresh   " translate the current document again now
:MDView lang off       " the original again, at once
```

It is **off by default**, and nothing of your text goes to any translation
engine until you switch it on. Right before the first request of a session the
message names the engine the text goes to (it follows `language.nvim`'s
configuration, the fallback chain included, so the engine named is the one that
really gets the text; it is named again if another engine takes over). With an
engine that is not usable nothing is sent and there is no notice, only the
failure message. Switching it off sends nothing any more: a run in flight is
cancelled, its late answers are dropped, and the original of every document a
tab shows goes out again at once.

**How it works.** mdview is a text mirror: every push into the preview passes
one place (`core/mirror.lua` into `core/display.lua`). The translation is done
by [language.nvim](../companion-plugins.md) (`translate_markdown`, with `deepl`,
`google`, `shell`, `custom` or the `ai` engine through ai.nvim). It is looked up
with `pcall(require)` and is never a hard dependency: without it mdview warns
once and the preview stays original. Code, link targets, front matter, HTML and
placeholders never go to the engine, an unusable paragraph stays original, and
the result has **exactly as many lines as the buffer**. That is what keeps every
line-based feature valid without a change in the browser: scroll sync, the
cursor marker, click-to-navigate, task-checkbox sync and the fenced-code spans
(`browser.highlighter = "nvim"`).

**Stale-while-revalidate.** A push is never delayed by the translation:

1. a valid text goes out at once: every paragraph whose translation is cached is
   translated, the rest is original (nothing leaves the machine for this step).
   For an edit of a document that was shown before, this is a plain line
   comparison instead (the translation around the edited lines is kept, the
   edited lines are original until the pause), because the cache lookup parses
   the whole document (about 0.4 s at 20 000 lines) and an edit pushes every
   150 ms. The comparison is made with the text the push before it showed, so
   edits in several places one after the other (under the `save` and `manual`
   triggers no run finishes in between) and an edit while a run is still going
   (it keeps what that run translated so far) all stay cheap. An edit that
   touches the structure takes the cache lookup after all:
   it can change what the lines around it are, and in-page links follow the
   translated headings. That is an edit (old or new text) of
   - a fence, a math block, an HTML comment, or a line that opens or closes an
     HTML block (`<pre>`, `<script>`, `<div>`, `</pre>`, `<?php`, also in a
     quote),
   - a heading, a setext underline (`===`, `---`, also one anywhere in the
     block below the edit: the edited lines are the text of that heading), a
     thematic break, or the line of a front matter,
   - the first two lines of the document (a front matter is decided there; with
     a `---` front matter, up to its first line with content),
   - a blank line added, removed or filled while an HTML block starts in the
     block above it, or above a line that depends on an open paragraph (a lone
     tag, indented code).

   The lines around such an edit are not part of it: typing into the blank line
   under a heading or into a code block is a plain edit. After a structural
   edit the next plain one is compared with the parse that answered it, so one
   structural edit costs one cache lookup, not one per push until the next run.
   The check is a heuristic on lines, not a parser: what it does not look at (a
   list item or a table that the edit starts or ends) keeps the old translation
   of the lines around it until the pause, and the full run then corrects it.
   Within a paragraph that is edited in only some of its lines, the other lines
   keep their translation until the pause;
2. the paragraphs that are translated afterwards are patched into the preview as
   they finish (about every 150 ms at most);
3. the finished document goes out last.

Every push bumps a generation counter of the room it goes to. A result of an
older generation (fast edits, or, with `browser.behavior = "reuse"`, a switch to
another buffer: the one preview tab is one room for every document) is dropped
and its run is cancelled, so one document's translation is never shown for
another. Wiping the buffer (or removing the option from the config) stops its run
the same way.

**When it translates** (`browser.display_lang_trigger`; never per keystroke):

| Trigger | The engine is asked |
| --- | --- |
| `"idle"` (default) | `browser.display_lang_debounce_ms` (800) after the last edit, on save, on a buffer switch, at start |
| `"save"` | on `:write`, on a buffer switch, at start |
| `"manual"` | only on `:MDView lang <code>` and `:MDView lang refresh` |

**When it cannot.** language.nvim missing, the engine unusable (for an `ai`
engine that is not usable, language.nvim reports it instead of using another
third party), a request that fails, a result with the wrong line count: the
original stays visible, the problem is reported **once**, never an empty or half
document. A paragraph that fails stays German while the rest is English.

**State in the browser.** A small badge in the corner (`Translating to en via
google … 3/12`, `Translated to en`, `Original, translation failed: ...`) says
that the text is a translation and how far it is. It rides the existing control
message (`displayLang`); a relay or a client from before this feature simply
ignores it. `:checkhealth mdview` lists language.nvim, the engine and whether it
can work (a key it needs is set); the key itself is never printed.

**Reverse paths.** Ticking a task checkbox still works: the browser names the
line, mdview flips only the marker in the real line of the real buffer, and the
next push translates it again. Text-field sync (writing an edited `<input>` or
`<textarea>` back) is **off** while the preview shows a transformed text: what
the browser sends belongs to the translation, not to the buffer.

**The generic hook.** `display_lang` is the built-in user of a hook you can use
yourself:

```lua
require("mdview").setup({ browser = {
  transform = function(lines, ctx, cb)
    -- ctx: path, bufnr, target, display_lang, reason, final
    cb(my_lines) -- exactly #lines lines; may be called later
  end,
} })
```

`cb` may run later (or never: the previous text stays). A result of another
length, or with a line that itself contains a line break, is dropped and
reported once. While the hook runs, the lines that did not change since its last
result show that result, the edited ones are original. With both set, the language runs first and
the hook sees its output (also the cache-only first text and the patches:
`ctx.final` tells them apart).

**Not supported (by design).**

- Standalone mode (`:MDView standalone`): the relay reads the file itself, so
  there is no Lua side that could translate it. The command refuses while
  `display_lang` or `transform` is set and says how to proceed.
- Several tabs with different languages at once (it would need one room per
  language).
- Column-exact mirrors in the translated text (selection mirror, spotlight
  matches): only whole lines keep their meaning.
- The in-editor preview tab (`:MDView preview-tab`) shows the buffer text; it is
  not translated.
- A pinned preview (`:MDView pin`) holds the document as it is; turn the pin off
  to translate it.

- **Module:** `lua/mdview/core/display.lua`, `lua/mdview/core/mirror.lua` (`lines_async`), `lua/mdview/bindings/usrcmds/lang.lua`; the badge in `src/client/render/langStatus.ts`
- **Usercmds:** `:MDView lang`
- **Config:** `browser.display_lang` (default `nil` = off), `browser.display_lang_trigger` (`"idle"`), `browser.display_lang_debounce_ms` (`800`), `browser.display_lang_source`, `browser.display_lang_engine`, `browser.transform`

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

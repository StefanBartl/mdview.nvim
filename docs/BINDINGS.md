# mdview.nvim — Commands, Autocommands & Keymaps

## User commands

mdview.nvim registers a single `:MDView <subcommand>` command (built via
[`lib.nvim.usercmd.composer`](https://github.com/StefanBartl/lib.nvim)), with
`<Tab>` completion for every subcommand and typed argument below.

| Command | Args | Description |
| --- | --- | --- |
| `:MDView start [file] [cwd=...]` | optional file path and/or `cwd=...` override, any order, `complete=file` | Spawns the mdview-server relay (downloading it on first use), attaches buffer-change autocommands, and opens the browser preview. If `file` is given, that file is targeted instead of the current buffer. `cwd=...` overrides `mdview.config.defaults.server_cwd` for this spawn only (ignored if a server is already running). |
| `:MDView stop` | none | Stops the relay process, detaches autocommands, shuts down the session, and (if `mdview.config.browser.browser_autoclose` is true) closes the browser tab it opened. |
| `:MDView toggle [file] [cwd=...]` | same as `:MDView start`, `complete=file` | Starts the preview if no session is running, otherwise stops it. Thin dispatcher over `:MDView start`/`:MDView stop`; start-style args are forwarded when starting, ignored when stopping. |
| `:MDView open` | none | Re-opens a browser tab for the current buffer against the **already-running** session (does not start a new server — requires `:MDView start` first). Pushes the current buffer's content so the new tab isn't empty, then opens the browser via the same key/token URL logic `:MDView start` uses. Fails loudly with `vim.notify` if no session is running. |
| `:MDView theme [name]` | optional theme name, `complete` over known themes | Switches the preview theme at runtime (`github` \| `dark-dimmed` \| `plain`, optionally `-light`/`-dark`). Sets `browser.theme` and re-opens the preview if a session is running; no argument reports the current theme. |
| `:MDView weblogs` | none | Opens a scratch buffer showing the relay server's stdout/stderr log, including `[client]` browser-side diagnostics POSTed back to the relay. |
| `:MDView log [level]` | optional level filter (`trace`\|`debug`\|`info`\|`warn`\|`error`) | Shows mdview's own internal structured log ring (launcher/live-push/ws_client/…) in a scratch buffer — distinct from the relay's stdout. Filters to that level and above. |
| `:MDView log export [path]` | optional output path, `complete=file` | Writes the internal log ring to a file (default: `stdpath('log')/mdview-log.txt`). |
| `:MDView file-log` | none | Toggles **persistent file logging** of the relay's stdout, then reports the state. Opt-in and off by default (`file_log`), so a plain `:MDView start` writes nothing to disk. |
| `:MDView file-log on [path]` | optional path, `complete=file` | Enables persistent file logging (optionally setting its path). Output goes to `file_log_path` — default `stdpath('log')/mdview/relay-<timestamp>.log`, never a `logs/` dir in the cwd. |
| `:MDView file-log off` | none | Disables persistent file logging. |
| `:MDView file-log status` | none | Reports the current on/off state and path without changing anything. |
| `:MDView file-log path [value]` | optional value (a path, or `default`), `complete=file` | Sets the file log path; `~`/relative paths are expanded to absolute when the command runs, so a later `:cd` doesn't move the file. `path` alone reports the current path; `path default` restores the configured default. |
| `:MDView diagnose [path]` | optional output path, `complete=file` | Writes a full component-state diagnostics report (environment, deps, install cache, config, running session + live `/health` probe, browser URL, recent log ring) to a file and opens it. |
| `:MDView preview-tab` | none | Toggles an nvim-tab Markdown preview for the current buffer — a read-only, Treesitter-highlighted (falls back to Vim's bundled `syntax=markdown` if the parser isn't installed) mirror buffer in its own tab. **No browser, no relay server, no HTML rendering at all** — fully decoupled from `:MDView start`/the WASM pipeline; works standalone. If `mdview.config.defaults.open_preview_tab` is `true`, `:MDView start` opens this instead of the browser (the relay/WASM pipeline still runs in the background, so `:MDView open` can still open the browser later). See [`adapter/preview_tab.lua`](../lua/mdview/adapter/preview_tab.lua). |

### Live preview controls

These change the **open** preview tab without a reload: each sets the matching
`browser.*` config (so a re-opened tab keeps it) and, while a session runs,
pushes a `\x05` control update over the socket.

| Command | Args | Description |
| --- | --- | --- |
| `:MDView cursor [mode]` | optional `line`\|`caret`\|`section`\|`off`, completed | Sets the Neovim-cursor marker in the preview (`browser.cursor_marker`): `line` (bar at the cursor line), `caret` (exact cursor column, via inline source-position spans), `section` (spotlight the current heading section, dim the rest), `off`. No argument reports the current mode. |
| `:MDView sync [action]` | optional `pause`\|`resume`\|`toggle`, completed | Pauses/resumes the outgoing nvim→browser scroll sync. While paused, `CursorMoved` sends no pings, so you can jump to a reference spot without dragging a viewer along, and the open tab shows a "⏸ scroll sync paused" pill. No argument reports the state. |
| `:MDView zoom [step]` | optional `+`\|`-`\|`reset`\|`<factor>`, completed | Adjusts the preview font-size zoom (`browser.zoom`). `+`/`-` step 10% (clamped 50–300%), `reset` = 100%, a bare number is a factor (`1.5`) or percent (`150`). No argument reports the current zoom. |
| `:MDView reveal [action]` | optional `on`\|`off`\|`toggle`, completed | Reveals/hides all private blocks (```` ```private ````, rendered blurred by default) by toggling `.mdview-reveal-all` on the preview root. Live-only, nothing persisted; individual blocks also reveal on click. No argument toggles. |
| `:MDView blanklines [action]` | optional `on`\|`off`\|`toggle`, completed | Toggles rendering runs of ≥2 consecutive blank lines as visible vertical space (`browser.preserve_blank_lines`). Sets the config value (a reopened tab keeps it) and re-renders the open tab live. No argument toggles. |
| `:MDView overlay [name] [action]` | optional overlay name + `on`\|`off`\|`toggle`, both completed | Toggles a preview overlay (`browser.overlays`) — currently `toc`, a floating outline with the current section highlighted. No name lists the known overlays and their state. |
| `:MDView overlay list` | none | Lists the known overlays and whether each is on. |
| `:MDView breadcrumbs` | none | Shows the session breadcrumbs (document + nearest heading over time) as a Markdown outline in a scratch buffer. |
| `:MDView breadcrumbs export [path]` | optional output path, `complete=file` | Writes the breadcrumbs outline to a file (default `stdpath('log')/mdview-breadcrumbs.md`). |
| `:MDView breadcrumbs clear` | none | Discards the recorded breadcrumbs. |

Every subcommand is an action module in [`bindings/usrcmds/`](../lua/mdview/bindings/usrcmds/),
one per file, aggregated into the `:MDView` route tree in
[`bindings/usrcmds/init.lua`](../lua/mdview/bindings/usrcmds/init.lua).

## Autocommands

All registered in a single augroup (`MdviewAutocmds`), created by [`mdview.bindings.autocmds.attach()`](../lua/mdview/bindings/autocmds/init.lua) and torn down together by `:MDView stop`.

| Event | Module | Purpose |
| --- | --- | --- |
| `BufEnter` | [`bindings/autocmds/bufenter.lua`](../lua/mdview/bindings/autocmds/bufenter.lua) | Takes a session snapshot of the entered buffer. |
| `TextChanged`, `TextChangedI` | [`bindings/autocmds/live_push.lua`](../lua/mdview/bindings/autocmds/live_push.lua) | Pushes the full current buffer content to the relay server for live preview. |
| `BufWritePost` | [`bindings/autocmds/live_push.lua`](../lua/mdview/bindings/autocmds/live_push.lua) | Same full push, triggered on save. |
| `CursorMoved`, `CursorMovedI` | [`bindings/autocmds/scroll_sync.lua`](../lua/mdview/bindings/autocmds/scroll_sync.lua) | Sends the cursor's line + total line count to the relay (throttled), so the browser preview scrolls to follow. Nvim-to-browser only. Gated behind `mdview.config.defaults.scroll_sync` (default `true`). |
| `CursorMoved`, `CursorMovedI`, `BufEnter` | [`bindings/autocmds/breadcrumbs.lua`](../lua/mdview/bindings/autocmds/breadcrumbs.lua) | Records session breadcrumbs (document + nearest heading, deduped on change) for `:MDView breadcrumbs`. Throttled. Gated behind `mdview.config.defaults.breadcrumbs` (default `true`). |
| `VimLeavePre` | [`bindings/autocmds/vim_leave.lua`](../lua/mdview/bindings/autocmds/vim_leave.lua) | Stops the relay server process so it doesn't outlive the Neovim session. **Not** pattern-restricted to markdown files — it must always fire regardless of which buffer is focused when Neovim quits. |

Two additional autocmd modules exist but are intentionally **not** wired up (`bindings/autocmds/on_text_change.lua`, `bindings/autocmds/bufwrite.lua`) — kept only for reference; `live_push.lua` supersedes both.

[`bindings/autocmds/preview_tab_sync.lua`](../lua/mdview/bindings/autocmds/preview_tab_sync.lua) registers its own `TextChanged`/`TextChangedI`/`BufWritePost` autocmds in a **separate** augroup (`MdviewPreviewTabSync`), created lazily the first time `:MDView preview-tab` opens a preview — independent of `MdviewAutocmds` and `:MDView start`/`:MDView stop`'s lifecycle entirely.

## Keymaps

mdview.nvim does not define any keymaps itself — only the `:MDView` command above. If you want a keymap, map it to a subcommand directly, e.g.:

```lua
vim.keymap.set("n", "<leader>mp", "<cmd>MDView start<cr>", { desc = "mdview: start preview" })
vim.keymap.set("n", "<leader>mq", "<cmd>MDView stop<cr>", { desc = "mdview: stop preview" })
vim.keymap.set("n", "<leader>ms", "<cmd>MDView sync toggle<cr>", { desc = "mdview: freeze/unfreeze scroll sync" })
```

The `sync toggle` map is handy while screen-sharing: freeze the preview, scroll around in Neovim to look something up, then unfreeze — the viewer never sees the jump.

Since these are plain `vim.keymap.set` calls with a `desc`, they show up correctly in [which-key.nvim](https://github.com/folke/which-key.nvim) without any extra integration needed.

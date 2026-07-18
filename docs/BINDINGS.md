# mdview.nvim — Commands, Autocommands & Keymaps

## User commands

| Command | Args | Description |
| --- | --- | --- |
| `:MDViewStart [file] [cwd=...]` | optional file path and/or `cwd=...` override, any order, `complete=file` | Spawns the mdview-server relay (downloading it on first use), attaches buffer-change autocommands, and opens the browser preview. If `file` is given, that file is targeted instead of the current buffer. `cwd=...` overrides `mdview.config.defaults.server_cwd` for this spawn only (ignored if a server is already running). |
| `:MDViewStop` | none | Stops the relay process, detaches autocommands, shuts down the session, and (if `mdview.config.browser.browser_autoclose` is true) closes the browser tab it opened. |
| `:MDViewToggle [file] [cwd=...]` | same as `:MDViewStart`, `complete=file` | Starts the preview if no session is running, otherwise stops it. Thin dispatcher over `:MDViewStart`/`:MDViewStop`; start-style args are forwarded when starting, ignored when stopping. |
| `:MDViewOpen` | none | Re-opens a browser tab for the current buffer against the **already-running** session (does not start a new server — requires `:MDViewStart` first). Pushes the current buffer's content so the new tab isn't empty, then opens the browser via the same key/token URL logic `:MDViewStart` uses. Fails loudly with `vim.notify` if no session is running. |
| `:MDViewTheme [name]` | optional theme name, `complete` over known themes | Switches the preview theme at runtime (`github` \| `dark-dimmed` \| `plain`, optionally `-light`/`-dark`). Sets `browser.theme` and re-opens the preview if a session is running; no argument reports the current theme. |
| `:MDViewShowWebLogs` | none | Opens a scratch buffer showing the relay server's stdout/stderr log, including `[client]` browser-side diagnostics POSTed back to the relay. |
| `:MDViewLog [level \| export [path]]` | optional level filter or `export [path]` | Shows mdview's own internal structured log ring (launcher/live-push/ws_client/…) in a scratch buffer — distinct from the relay's stdout. Filter by minimum level (`trace`/`debug`/`info`/`warn`/`error`) or `export` to a file. |
| `:MDViewFileLog [on\|off\|toggle\|status]` | optional subcommand, `complete` over `on`/`off`/`toggle`/`status` | Toggles **persistent file logging** of the relay's stdout at runtime. Opt-in and off by default (`file_log`), so a plain `:MDViewStart` writes nothing to disk. When on, lines are appended to `file_log_path` — default `stdpath('log')/mdview/relay-<timestamp>.log`, never a `logs/` dir in the cwd. No argument flips the state; `status` only reports. |
| `:MDViewDiagnose [path]` | optional output path, `complete=file` | Writes a full component-state diagnostics report (environment, deps, install cache, config, running session + live `/health` probe, browser URL, recent log ring) to a file and opens it. |
| `:MDViewPreviewTab` | none | Toggles an nvim-tab Markdown preview for the current buffer — a read-only, Treesitter-highlighted (falls back to Vim's bundled `syntax=markdown` if the parser isn't installed) mirror buffer in its own tab. **No browser, no relay server, no HTML rendering at all** — fully decoupled from `:MDViewStart`/the WASM pipeline; works standalone. If `mdview.config.defaults.open_preview_tab` is `true`, `:MDViewStart` opens this instead of the browser (the relay/WASM pipeline still runs in the background, so `:MDViewOpen` can still open the browser later). See [`adapter/preview_tab.lua`](../lua/mdview/adapter/preview_tab.lua). |

## Autocommands

All registered in a single augroup (`MdviewAutocmds`), created by [`mdview.bindings.autocmds.attach()`](../lua/mdview/bindings/autocmds/init.lua) and torn down together by `:MDViewStop`.

| Event | Module | Purpose |
| --- | --- | --- |
| `BufEnter` | [`bindings/autocmds/bufenter.lua`](../lua/mdview/bindings/autocmds/bufenter.lua) | Takes a session snapshot of the entered buffer. |
| `TextChanged`, `TextChangedI` | [`bindings/autocmds/live_push.lua`](../lua/mdview/bindings/autocmds/live_push.lua) | Pushes the full current buffer content to the relay server for live preview. |
| `BufWritePost` | [`bindings/autocmds/live_push.lua`](../lua/mdview/bindings/autocmds/live_push.lua) | Same full push, triggered on save. |
| `CursorMoved`, `CursorMovedI` | [`bindings/autocmds/scroll_sync.lua`](../lua/mdview/bindings/autocmds/scroll_sync.lua) | Sends the cursor's line + total line count to the relay (throttled), so the browser preview scrolls to follow. Nvim-to-browser only. Gated behind `mdview.config.defaults.scroll_sync` (default `true`). |
| `VimLeavePre` | [`bindings/autocmds/vim_leave.lua`](../lua/mdview/bindings/autocmds/vim_leave.lua) | Stops the relay server process so it doesn't outlive the Neovim session. **Not** pattern-restricted to markdown files — it must always fire regardless of which buffer is focused when Neovim quits. |

Two additional autocmd modules exist but are intentionally **not** wired up (`bindings/autocmds/on_text_change.lua`, `bindings/autocmds/bufwrite.lua`) — kept only for reference; `live_push.lua` supersedes both.

[`bindings/autocmds/preview_tab_sync.lua`](../lua/mdview/bindings/autocmds/preview_tab_sync.lua) registers its own `TextChanged`/`TextChangedI`/`BufWritePost` autocmds in a **separate** augroup (`MdviewPreviewTabSync`), created lazily the first time `:MDViewPreviewTab` opens a preview — independent of `MdviewAutocmds` and `:MDViewStart`/`:MDViewStop`'s lifecycle entirely.

## Keymaps

mdview.nvim does not define any keymaps itself — only the user commands above. If you want a keymap, map it to the command directly, e.g.:

```lua
vim.keymap.set("n", "<leader>mp", "<cmd>MDViewStart<cr>", { desc = "mdview: start preview" })
vim.keymap.set("n", "<leader>mq", "<cmd>MDViewStop<cr>", { desc = "mdview: stop preview" })
```

Since these are plain `vim.keymap.set` calls with a `desc`, they show up correctly in [which-key.nvim](https://github.com/folke/which-key.nvim) without any extra integration needed.

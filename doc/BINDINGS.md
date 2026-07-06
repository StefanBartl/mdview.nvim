# mdview.nvim — Commands, Autocommands & Keymaps

## User commands

| Command | Args | Description |
| --- | --- | --- |
| `:MDViewStart [file]` | optional file path, `complete=file` | Spawns the mdview-server relay (downloading it on first use), attaches buffer-change autocommands, and opens the browser preview. If `file` is given, that file is targeted instead of the current buffer. |
| `:MDViewStop` | none | Stops the relay process, detaches autocommands, shuts down the session, and (if `mdview.config.browser.browser_autoclose` is true) closes the browser tab it opened. |
| `:MDViewOpen` | none | **Not yet implemented** — calls `require("mdview").open()`, which doesn't exist yet; currently a no-op (see [doc/Roadmap/Roadmap.md](Roadmap/Roadmap.md)). |
| `:MDViewShowWebLogs` | none | Opens a scratch buffer showing the relay server's stdout/stderr log. |

## Autocommands

All registered in a single augroup (`MdviewAutocmds`), created by [`mdview.bindings.autocmds.attach()`](../lua/mdview/bindings/autocmds/init.lua) and torn down together by `:MDViewStop`.

| Event | Module | Purpose |
| --- | --- | --- |
| `BufEnter` | [`bindings/autocmds/bufenter.lua`](../lua/mdview/bindings/autocmds/bufenter.lua) | Takes a session snapshot of the entered buffer. |
| `TextChanged`, `TextChangedI` | [`bindings/autocmds/live_push.lua`](../lua/mdview/bindings/autocmds/live_push.lua) | Pushes the full current buffer content to the relay server for live preview. |
| `BufWritePost` | [`bindings/autocmds/live_push.lua`](../lua/mdview/bindings/autocmds/live_push.lua) | Same full push, triggered on save. |
| `VimLeavePre` | [`bindings/autocmds/vim_leave.lua`](../lua/mdview/bindings/autocmds/vim_leave.lua) | Stops the relay server process so it doesn't outlive the Neovim session. |

Two additional autocmd modules exist but are intentionally **not** wired up (`bindings/autocmds/on_text_change.lua`, `bindings/autocmds/bufwrite.lua`) — kept only for reference; `live_push.lua` supersedes both.

## Keymaps

mdview.nvim does not define any keymaps itself — only the user commands above. If you want a keymap, map it to the command directly, e.g.:

```lua
vim.keymap.set("n", "<leader>mp", "<cmd>MDViewStart<cr>", { desc = "mdview: start preview" })
vim.keymap.set("n", "<leader>mq", "<cmd>MDViewStop<cr>", { desc = "mdview: stop preview" })
```

Since these are plain `vim.keymap.set` calls with a `desc`, they show up correctly in [which-key.nvim](https://github.com/folke/which-key.nvim) without any extra integration needed.

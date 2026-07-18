# Configuration

All defaults live in [`lua/mdview/config/DEFAULTS.lua`](../lua/mdview/config/DEFAULTS.lua) — every key is typed via EmmyLua annotations there. Override any subset (including nested `browser`/`start`/`install` tables) through `setup()`:

```lua
require("mdview").setup({
  server_port = 43219,
  browser = { browser = "firefox", browser_autostart = false },
  start = { push_strategy = "try_push" },
  install = { repo = "your-fork/mdview.nvim", version = "v0.2.0" },
})
```

Partial nested overrides merge recursively — `{ browser = { browser = "firefox" } }` only changes that one key, the rest of `browser`'s defaults stay intact.

## Key options

| Option | Default | Purpose |
| --- | --- | --- |
| `server_port` | `43219` | Preferred loopback port; the relay picks the next free one if taken. |
| `scroll_sync` | `true` | Sync the nvim cursor position to the browser scroll position (line-accurate via comrak sourcepos). |
| `scroll_sync_mode` | `"top"` | Where the cursor line lands in the browser viewport: `"top"` (near the top; `scroll_sync_top_offset` = fraction down, `0` = glued to top) or `"cursor"` (mirror — same relative height as the cursor in the nvim window). |
| `open_preview_tab` | `false` | Render into a read-only Neovim tab (Treesitter-highlighted) instead of the browser. |
| `browser.open_mode` | `"default"` | `"default"` opens a tab in your normal browser (your extensions/theme; auto-close via a cooperative `window.close()` on stop). `"isolated"` spawns a throwaway profile so process-handle auto-close works. |
| `browser.behavior` | `"reuse"` | What happens when you switch markdown buffers: `"reuse"` (the one tab follows the active buffer), `"new_tab"` (each file opens its own tab), or `"manual"` (nothing; use `:MDViewOpen`). |
| `browser.theme` | `"github"` | Preview theme: `github`, `dark-dimmed`, `plain`, `tokyonight`, or `catppuccin` — optionally suffixed `-light`/`-dark` to pin the color scheme. |
| `browser.highlighter` | `"hljs"` | Code-fence syntax highlighter (client-side, lazy-loaded): `"hljs"` (highlight.js, light), `"shiki"` (exact TextMate/VSCode themes — tokyo-night, catppuccin, dark-plus — heavier), or `"none"`. |
| `browser.external_links` | `"new_tab"` | Where external links (`http(s):`, other schemes, protocol-relative) open when clicked: `"new_tab"` (open in a new browser tab so the preview tab stays put) or `"same_tab"` (let the browser navigate away). In-project relative links are unaffected — those are handled by `experimental.click_navigate`. |
| `browser.cursor_marker` | `"line"` | Overlay a marker in the preview at the Neovim cursor's line: `"line"` (a blinking bar at the cursor line, approximate) or `"off"`. Column-accurate placement (via an exact source map) is a planned follow-up. |
| `browser.focus` | `"browser"` | Whether the opened tab may take keyboard focus (`"browser"`) or focus stays in Neovim (`"nvim"`). `"nvim"` is clean on macOS (`open -g`), best-effort on Windows, and a no-op on Linux. `default` open_mode only. |
| `browser.browser_autostart` | `true` | Open the browser automatically on `:MDViewStart`. |
| `browser.stop_on_browser_exit` | `true` | Run `:MDViewStop` when the opened browser process exits (isolated mode only). |
| `browser.require_display` | `true` | Don't try to open a browser without a GUI/`DISPLAY`. |
| `experimental.line_diff` | `false` | Opt in to sending only changed lines per edit (versioned diff transport) instead of the whole document. Saves bandwidth on large files; rendering still processes the whole doc client-side. Self-heals from any desync on the next full snapshot (save / every 25 edits). |
| `experimental.click_navigate` | `true` | Click-to-navigate: clicking a relative link in the preview opens the linked document in Neovim (resolved against the source doc), which then flows back into the preview. External links, anchors, and absolute paths are left to the browser. Set `false` to let the browser follow links itself. |
| `experimental.reverse_scroll` | `false` | Opt in to reverse scroll: scrolling the preview moves Neovim's cursor to match (the complement of the always-on nvim→browser scroll sync). Polled, so it follows with a small lag. |
| `experimental.webtransport` | `false` | Opt in to the WebTransport (HTTP/3) client transport; falls back to WebSocket until an HTTP/3 relay backend exists (future tech). |

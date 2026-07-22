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
| `browser.behavior` | `"reuse"` | What happens when you switch markdown buffers: `"reuse"` (the one tab follows the active buffer), `"new_tab"` (each file opens its own tab), or `"manual"` (nothing; use `:MDView open`). |
| `browser.theme` | `"github"` | Preview theme: `github`, `dark-dimmed`, `plain`, `tokyonight`, or `catppuccin` — optionally suffixed `-light`/`-dark` to pin the color scheme. |
| `browser.highlighter` | `"hljs"` | Code-fence syntax highlighter (client-side, lazy-loaded): `"hljs"` (highlight.js, light), `"shiki"` (exact TextMate/VSCode themes — tokyo-night, catppuccin, dark-plus — heavier), or `"none"`. |
| `browser.external_links` | `"new_tab"` | Where external links (`http(s):`, other schemes, protocol-relative) open when clicked: `"new_tab"` (open in a new browser tab so the preview tab stays put) or `"same_tab"` (let the browser navigate away). In-project relative links are unaffected — those are handled by `experimental.click_navigate`. |
| `browser.cursor_marker` | `"line"` | Show the Neovim cursor in the preview: `"line"` (a blinking bar in the left gutter at the cursor line), `"caret"` (an exact caret at the cursor column, via inline source-position spans), `"section"` (spotlight the current heading section, dim the rest), or `"off"`. Change live with `:MDView cursor`. |
| `browser.zoom` | `1.0` | Preview font-size zoom factor (`1.0` = 100%). Adjust live with `:MDView zoom`; a reopened tab starts at the last set value. |
| `browser.preserve_blank_lines` | `false` | Render runs of ≥2 consecutive blank lines as visible vertical space instead of collapsing them (CommonMark default). Toggle live with `:MDView blanklines [on\|off\|toggle]`. Sourcepos-safe, so scroll sync and the cursor caret stay accurate; blank lines inside fenced code are always preserved. |
| `browser.overlays` | `{ toc = false }` | Which preview overlays start enabled (e.g. floating TOC). Toggle live with `:MDView overlay <name> [on\|off\|toggle]`. |
| `browser.focus` | `"browser"` | Whether the opened tab may take keyboard focus (`"browser"`) or focus stays in Neovim (`"nvim"`). `"nvim"` is clean on macOS (`open -g`), best-effort on Windows, and a no-op on Linux. `default` open_mode only. |
| `browser.browser_autostart` | `true` | Open the browser automatically on `:MDView start`. |
| `browser.stop_on_browser_exit` | `true` | Run `:MDView stop` when the opened browser process exits (isolated mode only). |
| `browser.require_display` | `true` | Don't try to open a browser without a GUI/`DISPLAY`. |
| `standalone.binary_path` | `nil` | Relay binary `:MDView standalone` spawns; `nil` uses the one `install` manages. Standalone mode needs a relay with `--watch` support (v0.3.0+) — set this to run a locally built or newer one. See [standalone.md](standalone.md). |
| `dev.binary_path` | `nil` | **Developer-only.** Absolute path to a locally built `mdview-server` that `:MDView start` runs instead of the downloaded `install.version` release — so features newer than the pinned release actually run. Falls back to `$MDVIEW_DEV_BINARY`. See [development.md](development.md#running-your-local-build-inside-neovim). |
| `dev.web_root` | `nil` | **Developer-only.** Path to a locally built client bundle (e.g. `dist/client`) passed to the relay as `--web-root` instead of the downloaded one. Falls back to `$MDVIEW_DEV_WEB_ROOT`. |
| `experimental.line_diff` | `false` | Opt in to sending only changed lines per edit (versioned diff transport) instead of the whole document. Saves bandwidth on large files; rendering still processes the whole doc client-side. Self-heals from any desync on the next full snapshot (save / every 25 edits). |
| `experimental.click_navigate` | `true` | Click-to-navigate: clicking a relative link in the preview opens the linked document in Neovim (resolved against the source doc), which then flows back into the preview. External links, anchors, and absolute paths are left to the browser. Set `false` to let the browser follow links itself. |
| `experimental.reverse_scroll` | `false` | Opt in to reverse scroll: scrolling the preview moves Neovim's cursor to match (the complement of the always-on nvim→browser scroll sync). Polled, so it follows with a small lag. |
| `experimental.webtransport` | `false` | Opt in to the WebTransport (HTTP/3) client transport; falls back to WebSocket until an HTTP/3 relay backend exists (future tech). |

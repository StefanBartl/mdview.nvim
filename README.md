🔧 Alpha stage – this project is highly experimental and under active development. Don't expect this plugin is working with your system yet.

```sh
   ##     ## ########  ##     ## #### ######## ##      ##           ##    ## ##     ## #### ##     ##
   ###   ### ##     ## ##     ##  ##  ##       ##  ##  ##           ###   ## ##     ##  ##  ###   ###
   #### #### ##     ## ##     ##  ##  ##       ##  ##  ##           ####  ## ##     ##  ##  #### ####
   ## ### ## ##     ## ##     ##  ##  ######   ##  ##  ##           ## ## ## ##     ##  ##  ## ### ##
   ##     ## ##     ##  ##   ##   ##  ##       ##  ##  ##           ##  ####  ##   ##   ##  ##     ##
   ##     ## ##     ##   ## ##    ##  ##       ##  ##  ##    ###    ##   ###   ## ##    ##  ##     ##
   ##     ## ########     ###    #### ########  ###  ###     ###    ##    ##    ###    #### ##     ##
```

> Inspired by and positioned as a security/performance-focused alternative to
> [iamcco/markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim).

![version](https://img.shields.io/badge/version-0.9-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lazy.nvim](https://img.shields.io/badge/lazy.nvim-supported-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![TypeScript](https://img.shields.io/badge/client-TypeScript-3178C6.svg)
![Server](https://img.shields.io/badge/server-Go-00ADD8.svg)
![WASM](https://img.shields.io/badge/WASM-ready-654FF0.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)
![Performance](https://img.shields.io/badge/optimized-true-success.svg)
![Build](https://img.shields.io/badge/build-edge%20runtime-informational.svg)
![Contributions](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)

---

## Overview

**mdview.nvim** is a **browser-based Markdown preview plugin for Neovim**.
A small Go relay server streams raw buffer content to the browser over
WebSocket; rendering and HTML sanitization happen entirely client-side in a
Rust module compiled to WebAssembly, so untrusted Markdown/HTML never gets
turned into DOM content without passing through an allowlist-based sanitizer.

**Key features:**
* Live browser preview for Markdown documents
* Automatic update on buffer change
* Sanitized HTML rendering (Rust/WASM: comrak + ammonia) — no server-side rendering step
* No Node/Go/Rust toolchain required to run it: the relay binary and client bundle are downloaded once from GitHub Releases
* Loopback-only server with per-session token + Origin checks

---

## Installation

**When to use which:**

| Variant | Startup impact | Commands available | When to use |
|---|---|---|---|
| **`ft`/`cmd` (Recommended)** | Minimal | On `:MDView*` or when opening a markdown file | Default — true lazy-loading |
| **`lazy = false`** | Loads immediately | Right from the start | Only if you want the plugin fully initialized before any command |

### lazy.nvim

*Lazy-load on markdown files or the plugin's own commands (recommended):*
```lua
{
  "StefanBartl/mdview.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  ft = { "markdown" },
  cmd = {
    "MDViewStart", "MDViewStop", "MDViewToggle", "MDViewOpen", "MDViewTheme",
    "MDViewPreviewTab", "MDViewShowWebLogs", "MDViewLog", "MDViewDiagnose",
  },
  config = function()
    require("mdview").setup()
  end,
}
```

*Load at startup (eager):*
```lua
{
  "StefanBartl/mdview.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  lazy = false,
  config = function()
    require("mdview").setup()
  end,
}
```

### packer

```lua
use {
  "StefanBartl/mdview.nvim",
  requires = { "StefanBartl/lib.nvim" },
  ft = { "markdown" },
  cmd = {
    "MDViewStart", "MDViewStop", "MDViewToggle", "MDViewOpen", "MDViewTheme",
    "MDViewPreviewTab", "MDViewShowWebLogs", "MDViewLog", "MDViewDiagnose",
  },
  config = function()
    require("mdview").setup()
  end,
}
```

No external toolchain is required to run the plugin — see [Development](#development) below only if you want to build mdview.nvim itself from source.

---

## Configuration

All defaults live in [`lua/mdview/config/DEFAULTS.lua`](lua/mdview/config/DEFAULTS.lua) — every key is typed via EmmyLua annotations there. Override any subset (including nested `browser`/`start`/`install` tables) through `setup()`:

```lua
require("mdview").setup({
  server_port = 43219,
  browser = { browser = "firefox", browser_autostart = false },
  start = { push_strategy = "try_push" },
  install = { repo = "your-fork/mdview.nvim", version = "v0.2.0" },
})
```

Partial nested overrides merge recursively — `{ browser = { browser = "firefox" } }` only changes that one key, the rest of `browser`'s defaults stay intact.

### Key options

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
| `browser.cursor_marker` | `"line"` | Overlay a marker in the preview at the Neovim cursor: `"line"` (a blinking bar at the cursor line), `"caret"` (a caret at the exact cursor column, via inline source-position spans from the renderer — falls back to the line marker on blank lines and inside code blocks), or `"off"`. Rides the scroll-sync ping, so needs `scroll_sync` on. Switch at runtime with `:MDViewCursor`. |
| `browser.zoom` | `1.0` | Preview font-size zoom factor (`1.0` = 100%). The whole document scales proportionally. Adjust at runtime with `:MDViewZoom`. |
| `browser.focus` | `"browser"` | Whether the opened tab may take keyboard focus (`"browser"`) or focus stays in Neovim (`"nvim"`). `"nvim"` is clean on macOS (`open -g`), best-effort on Windows, and a no-op on Linux. `default` open_mode only. |
| `browser.browser_autostart` | `true` | Open the browser automatically on `:MDViewStart`. |
| `browser.stop_on_browser_exit` | `true` | Run `:MDViewStop` when the opened browser process exits (isolated mode only). |
| `browser.require_display` | `true` | Don't try to open a browser without a GUI/`DISPLAY`. |
| `experimental.line_diff` | `false` | Opt in to sending only changed lines per edit (versioned diff transport) instead of the whole document. Saves bandwidth on large files; rendering still processes the whole doc client-side. Self-heals from any desync on the next full snapshot (save / every 25 edits). |
| `experimental.click_navigate` | `true` | Click-to-navigate: clicking a relative link in the preview opens the linked document in Neovim (resolved against the source doc), which then flows back into the preview. External links, anchors, and absolute paths are left to the browser. Set `false` to let the browser follow links itself. |
| `experimental.reverse_scroll` | `false` | Opt in to reverse scroll: scrolling the preview moves Neovim's cursor to match (the complement of the always-on nvim→browser scroll sync). Polled, so it follows with a small lag. When on, the preview shows a small "⇅ scroll enabled" hint so a viewer knows they may scroll it. |
| `experimental.webtransport` | `false` | Opt in to the WebTransport (HTTP/3) client transport; falls back to WebSocket until an HTTP/3 relay backend exists (future tech). |

---

## Commands

| Command | Description |
| --- | --- |
| `:MDViewStart [file] [cwd=…]` | Start the relay and open the preview for the current buffer (or the given file). |
| `:MDViewStop` | Stop the relay, detach autocommands, and (in isolated mode) close the browser. |
| `:MDViewToggle [file] [cwd=…]` | Start if stopped, stop if running. |
| `:MDViewOpen` | Re-open a browser tab against the already-running session (does not start a new relay). |
| `:MDViewTheme [name]` | Switch the preview theme at runtime (`github` \| `dark-dimmed` \| `plain` \| `tokyonight` \| `catppuccin`, optionally `-light`/`-dark`); no argument reports the current theme. |
| `:MDViewCursor [line\|caret\|off]` | Switch the Neovim-cursor marker mode in the preview at runtime (applies live, no reload); no argument reports the current mode. See `browser.cursor_marker`. |
| `:MDViewSync [pause\|resume\|toggle]` | Pause/resume the nvim→browser scroll sync. While paused, moving the cursor no longer scrolls the preview or moves its marker — jump to a reference spot without dragging a viewer along. No argument reports the state. |
| `:MDViewZoom [+\|-\|reset\|<factor>]` | Adjust the preview font-size zoom at runtime (applies live). `+`/`-` step by 10% (clamped 50–300%), `reset` = 100%, a bare number sets a factor (`1.5`) or percent (`150`); no argument reports the current zoom. See `browser.zoom`. |
| `:MDViewPreviewTab` | Toggle the in-Neovim tab preview (works standalone, no server needed). |
| `:MDViewShowWebLogs` | Show the relay's captured stdout, including `[client]` browser-side diagnostics. |
| `:MDViewLog [level\|export [path]]` | Show mdview's internal log ring (optionally filtered to `trace`/`debug`/`info`/`warn`/`error`), or `export` it to a file. |
| `:MDViewDiagnose [path]` | Write a full component-state diagnostics report to a file and open it. |

Run `:checkhealth mdview` to verify dependencies (lib.nvim, curl, tar) and whether the relay binary and client bundle are cached.

---

## Companion plugins (optional)

mdview.nvim is a **live mirror** of your Markdown buffer: it streams the raw
buffer text to the browser, which re-renders it. A useful consequence —

> **Any Neovim plugin that edits the buffer *text* is reflected in the preview
> for free.** You don't implement it in mdview; you just see the result.

- **[markdown.nvim](https://github.com/StefanBartl/markdown.nvim)** — a
  Markdown toolkit (TOC, reference updater, table formatter, heading shifting,
  …). Because those all transform the buffer text, running them updates the
  live preview automatically. Recommended companion, **not** a dependency.
- **[color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim)** —
  highlights fenced code / ASCII art **inside the Neovim buffer**. That's a
  Neovim-side rendering feature (highlight groups, not HTML), so it complements
  rather than feeds the browser preview — mdview does its own client-side code
  highlighting (`browser.highlighter`). Use both to get colored code in the
  editor *and* the browser.

Neither is required, and mdview never loads them; `:checkhealth mdview` just
notes when they're present.

---

## Development

To develop or contribute:

1. Clone the repository:

```bash
git clone https://github.com/StefanBartl/mdview.nvim
cd mdview.nvim
````

2. Load manually or via your preferred plugin manager.

3. Development requires Node.js 18+, Go 1.22+, and Rust with the
   `wasm32-unknown-unknown` target (`rustup target add wasm32-unknown-unknown`)
   plus [`wasm-pack`](https://rustwasm.github.io/wasm-pack/installer/).
   End users don't need any of this — the release binary and client bundle
   are downloaded automatically on first use.

```bash
npm install
npm run build   # builds the WASM render module + client bundle
npm run dev     # runs the Go relay + Vite dev server together
```

4. Make changes, test (`npm test`, `npm run test:go`, `npm run test:rust`,
   `npm run test:lua`), and submit pull requests or open issues.

**Contributions are welcome** – whether it’s a bugfix, optimization, or new feature idea.

---

## Architecture

| Component         | Technology              | Description                                                          |
| ----------------- | ----------------------- | ---------------------------------------------------------------------|
| **Core**          | Lua (+ [lib.nvim](https://github.com/StefanBartl/lib.nvim)) | Handles Neovim buffer events, state management, IPC   |
| **Server**        | Go                      | Loopback-only relay: file/buffer text in, WebSocket fan-out — no HTML |
| **Client**        | TypeScript              | Thin WebSocket glue + DOM injection of already-sanitized HTML        |
| **Communication** | WebSocket               | Buffer text in, sanitized HTML never leaves the browser               |
| **Rendering**     | Rust → WASM (comrak + ammonia) | Markdown → HTML + allowlist sanitization, both in the browser  |

---

## Disclaimer

ℹ️ mdview.nvim is under active development –
expect rapid iteration, experimental features, and evolving APIs.

---

## Feedback

Your feedback is very welcome!

Use the [GitHub Issue Tracker](https://github.com/StefanBartl/mdview.nvim/issues) to:

* Report bugs
* Suggest new features
* Ask usage questions
* Share thoughts on UI or workflow

For open discussion, visit the
[GitHub Discussions](https://github.com/StefanBartl/mdview.nvim/discussions).

If you find this plugin useful, please give it a ⭐ on GitHub to support its development.

---

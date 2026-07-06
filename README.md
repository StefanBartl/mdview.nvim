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
  cmd = { "MDViewStart", "MDViewStop", "MDViewOpen", "MDViewShowWebLogs" },
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
  cmd = { "MDViewStart", "MDViewStop", "MDViewOpen", "MDViewShowWebLogs" },
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

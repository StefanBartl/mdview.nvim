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

## Quickstart

*lazy.nvim, lazy-loaded on markdown files or the plugin's own commands (recommended):*
```lua
{
  "StefanBartl/mdview.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  ft = { "markdown" },
  cmd = { "MDView" },
  config = function()
    require("mdview").setup()
  end,
}
```

Then open a markdown file and run `:MDView start`. No external toolchain is required to run the plugin. See [Installation](docs/installation.md) for packer and eager-loading variants.

---

## Documentation

- [Installation](docs/installation.md) — lazy.nvim/packer setup variants and when to use each.
- [Configuration](docs/configuration.md) — all available `setup()` options and their defaults.
- [Commands](docs/commands.md) — full `:MDView <subcommand>` command reference and `:checkhealth mdview`.
- [Companion plugins](docs/companion-plugins.md) — optional plugins that pair well with the live preview.
- [Development](docs/development.md) — building mdview.nvim from source and running its test suites.
- [Architecture](docs/architecture.md) — the Lua/Go/TypeScript/Rust components and how they communicate.

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

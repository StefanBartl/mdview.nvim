> **Active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

> Alpha stage: highly experimental. Do not expect this plugin to work on your system yet.

# mdview.nvim

```sh
   ##     ## ########  ##     ## #### ######## ##      ##           ##    ## ##     ## #### ##     ##
   ###   ### ##     ## ##     ##  ##  ##       ##  ##  ##           ###   ## ##     ##  ##  ###   ###
   #### #### ##     ## ##     ##  ##  ##       ##  ##  ##           ####  ## ##     ##  ##  #### ####
   ## ### ## ##     ## ##     ##  ##  ######   ##  ##  ##           ## ## ## ##     ##  ##  ## ### ##
   ##     ## ##     ##  ##   ##   ##  ##       ##  ##  ##           ##  ####  ##   ##   ##  ##     ##
   ##     ## ##     ##   ## ##    ##  ##       ##  ##  ##    ###    ##   ###   ## ##    ##  ##     ##
   ##     ## ########     ###    #### ########  ###  ###     ###    ##    ##    ###    #### ##     ##
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-alpha-red)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)

> mdview.nvim is a **live mirror** of your Markdown buffer, not an editing
> toolkit — pair it with
> [markdown.nvim](https://github.com/StefanBartl/markdown.nvim) (TOC,
> reference updater, table formatter, heading shifting, …) for editing
> features. Since markdown.nvim only ever transforms buffer text, its edits
> show up in the live preview automatically. Recommended companion, not a
> dependency — see [Companion plugins](docs/companion-plugins.md).

> Inspired by and positioned as a security/performance-focused alternative to
> [iamcco/markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim).

---

## Table of Contents

- [Overview](#overview)
- [Quickstart](#quickstart)
- [Requirements](#requirements)
- [Documentation](#documentation)
- [Disclaimer](#disclaimer)
- [Feedback](#feedback)

---

## Overview

**mdview.nvim** is a **browser-based Markdown preview plugin for Neovim**.
A small Go relay server streams raw buffer content to the browser over
WebSocket; rendering and HTML sanitization happen entirely client-side in a
Rust module compiled to WebAssembly, so untrusted Markdown/HTML never gets
turned into DOM content without passing through an allowlist-based sanitizer.

**Key features:**
* Live browser preview for Markdown documents, with scroll sync (both directions), a cursor marker, click-to-navigate, and an in-editor tab preview that needs no browser or server
* Standalone preview that outlives Neovim — the relay watches the file on disk directly
* Sanitized HTML rendering (Rust/WASM: comrak + ammonia) — no server-side rendering step
* Runtime theme switching, preview zoom, floating overlays (table of contents), and a breadcrumbs session outline
* No Node/Go/Rust toolchain required to run it: the relay binary and client bundle are downloaded once from GitHub Releases
* Loopback-only server with per-session token + Origin checks
* Built-in diagnostics: internal log ring, persistent relay-log file, relay stdout viewer, and a one-shot full component-state report

---

## Capabilities

| Capability | What it does | Details |
|---|---|---|
| `:MDView start` / `stop` / `toggle` / `open` | Start, stop, or re-open the live browser preview session | [Commands](docs/commands.md) |
| `:MDView standalone` | Preview via the relay's own file watcher — outlives `:qa`, no Neovim in the chain | [Standalone](docs/standalone.md) |
| `:MDView preview-tab` | In-editor tab preview, no browser or server needed | [Preview](docs/FEATURES/PREVIEW.md#in-editor-preview-tab-no-browser-no-server) |
| `:MDView cursor` | Neovim cursor marker in the preview (line/caret/section spotlight) | [Preview](docs/FEATURES/PREVIEW.md#neovim-cursor-marker) |
| Task-list checkbox sync | Tick a `- [ ]` in the preview → written back to the source (`sync_checkboxes`) | [Preview](docs/FEATURES/PREVIEW.md#task-list-checkbox-sync) |
| Text field sync | Edit a `<input name>` / `<textarea name>` in the preview → written back to the source (`sync_fields`) | [Preview](docs/FEATURES/PREVIEW.md#text-field-sync) |
| `:MDView sync` | Pause/resume Neovim → browser scroll sync at runtime | [Preview](docs/FEATURES/PREVIEW.md#scroll-sync-pauseresume) |
| Reverse scroll / click-to-navigate | Browser scroll and clicks move the Neovim cursor back | [Preview](docs/FEATURES/PREVIEW.md#reverse-scroll-browser--neovim) |
| `:MDView zoom` | Adjust the preview's font-size scale independently of the browser | [Preview](docs/FEATURES/PREVIEW.md#preview-zoom) |
| `:MDView overlay` | Mount/unmount a floating overlay (table of contents) on the preview | [Preview](docs/FEATURES/PREVIEW.md#overlays-floating-table-of-contents) |
| `:MDView breadcrumbs` | Session outline of visited sections, exportable | [Preview](docs/FEATURES/PREVIEW.md#breadcrumbs-session-outline) |
| `:MDView reveal` | Reveal/hide private (fenced) blocks | [Rendering](docs/FEATURES/RENDERING.md#private-blocks) |
| `:MDView blanklines` | Toggle blank-line handling in rendered output | [Rendering](docs/FEATURES/RENDERING.md#blank-line-handling) |
| `:MDView theme` | Switch the preview theme at runtime | [Rendering](docs/FEATURES/RENDERING.md#themes) |
| `:MDView weblogs` / `log` / `file-log` / `diagnose` | Relay stdout viewer, internal log ring, persistent relay-log file, full diagnostics report | [Operations](docs/FEATURES/OPERATIONS.md) |
| Link hover previews | Preview a link's target inline in the browser | [Preview](docs/FEATURES/PREVIEW.md#link-hover-previews) |

---

## Quickstart

*lazy.nvim, lazy-loaded on markdown files or the plugin's own commands (recommended):*
```lua
{
  "StefanBartl/mdview.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  ft = { "markdown" },
  cmd = { "MDView" },
  opts = {},
}
```

Then open a markdown file and run `:MDView start`. No external toolchain is required to run the plugin. See [Installation](docs/installation.md) for packer and eager-loading variants.

---

## Requirements

`curl` (used to download the relay binary and client bundle on first use) —
declared in [`docs/install.json`](docs/install.json) and checked by
`:checkhealth mdview`. If [lib.nvim](https://github.com/StefanBartl/lib.nvim)'s
[`deps` module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md)
is available, a popup explains this the first time `setup()` runs after
installing mdview.nvim; `:Lib deps show mdview.nvim` repeats it any time.
Disable it **right in this plugin's own spec**:
`require("mdview").setup({ deps_popup = false })`.
`vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) /
`vim.g.lib_nvim_deps_disabled_plugins = { "mdview.nvim" }` also still
work, for turning it off without touching any plugin's config.

---

## Documentation

- [Installation](docs/installation.md) — lazy.nvim/packer setup variants and when to use each.
- [Configuration](docs/configuration.md) — all available `setup()` options and their defaults.
- [Commands](docs/commands.md) — full `:MDView <subcommand>` command reference and `:checkhealth mdview`.
- [Background & standalone](docs/standalone.md) — previews that outlive your Neovim instance, and running mdview with no Neovim at all.
- [Companion plugins](docs/companion-plugins.md) — optional plugins that pair well with the live preview.
- [Development](docs/development.md) — building mdview.nvim from source and running its test suites.
- [Architecture](docs/architecture.md) — the Lua/Go/TypeScript/Rust components and how they communicate.
- [Features](docs/FEATURES/README.md) — the catalog. The overview and what each theme covers, then per-theme depth in [preview](docs/FEATURES/PREVIEW.md) (incl. link hover previews), [rendering](docs/FEATURES/RENDERING.md), [operations](docs/FEATURES/OPERATIONS.md), [security](docs/FEATURES/SECURITY.md) and the [machinery](docs/FEATURES/FEATURES.md) underneath (caches, throttling, diff transport).

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

## License

MIT — see [LICENSE](LICENSE).

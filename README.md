> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

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
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)
[![CI](https://github.com/StefanBartl/mdview.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/mdview.nvim/actions/workflows/ci.yml)

A browser-based Markdown preview for Neovim that renders nothing on the server.

A small Go relay streams raw buffer text to the browser over WebSocket; the
rendering and the HTML sanitization both happen client-side, in a Rust module
compiled to WebAssembly. Untrusted Markdown never becomes DOM content without
passing an allowlist sanitizer first, and no toolchain is needed to run it —
the relay binary and the client bundle are downloaded once from GitHub
Releases.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Two previews, not one](#two-previews-not-one)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start with the [documentation index](docs/README.md) — it lists every page and
says what each one answers.

- [Features](docs/FEATURES/README.md) — the catalog, then per-theme depth: [preview](docs/FEATURES/PREVIEW.md), [rendering](docs/FEATURES/RENDERING.md), [operations](docs/FEATURES/OPERATIONS.md), [security](docs/FEATURES/SECURITY.md), and [the machinery underneath](docs/FEATURES/MACHINERY.md).
- [Installation](docs/installation.md) — the setup variants, and where the relay binary and client bundle come from.
- [Configuration](docs/configuration.md) — every `setup()` option and its default.
- [Command reference](docs/commands.md) — every `:MDView` subcommand.
- [Bindings cheatsheet](docs/BINDINGS.md) — commands, autocommands and keymaps at a glance, with the full argument shape of each.
- [Workflow](docs/WORKFLOW.md) — once a session is running: which controls apply live, which need a restart, what breaks first.
- [Standalone](docs/standalone.md) — a preview that outlives `:qa`, or runs with no Neovim at all.
- [Companion plugins](docs/companion-plugins.md) — which optional plugins pair with the live preview, and what each adds.
- [Architecture](docs/architecture.md) — which component is written in which language, and how they talk.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, the four-language layout, and how to change a component.
- [Development](docs/development.md) — building from source and running the four test suites.
- [Relay testing](docs/relay-testing.md) — driving the Go relay's endpoints by hand to pin a failure to one hop.
- [Diff harness](docs/diff-harness.md) — benchmarking and verifying the experimental line-diff transport.
- [Ecosystem architecture](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/ECOSYSTEM.md) — how docs, static analysis and runtime split across `lib.nvim`, `documentation.nvim`, `runtime-analysis.nvim` and mdview.nvim.

`:help mdview` is the same reference inside the editor.

---

## What it does

mdview.nvim is a **live mirror** of your Markdown buffer, not an editing
toolkit. It streams the raw buffer text and lets the browser re-render it,
which has a useful consequence: any plugin that edits the buffer *text* shows
up in the preview for free, without mdview knowing anything about it.

| Area | Does |
| --- | --- |
| **Live preview** | The buffer in a browser tab, with scroll sync both ways, a cursor marker, click-to-navigate, a visual-selection mirror, and document pinning |
| **Write-back** | Ticking a `- [ ]` in the preview, or editing an `<input>` / `<textarea>`, is written back into the source buffer |
| **Standalone** | The relay watching the file on disk directly, so the preview outlives `:qa` — or runs with no Neovim in the chain at all |
| **Rendering** | Runtime theme switching, preview zoom, blank-line handling, private fenced blocks, floating overlays, and a breadcrumbs session outline |
| **Security** | Client-side sanitization (comrak + ammonia, Rust/WASM), a loopback-only server, and per-session token plus Origin checks |
| **Operations** | An internal log ring, a persistent relay-log file, a relay stdout viewer, and a one-shot full component-state report |

The positioning is deliberate: this is the security- and performance-focused
alternative to
[iamcco/markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim),
which is what it was inspired by.

---

## Around it

> **[markdown.nvim](https://github.com/StefanBartl/markdown.nvim)** — the
> editing half: TOC, reference updater, table formatter, heading shifting.
> Because all of those transform buffer text, their edits appear in the live
> preview automatically.
>
> **[color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim)** —
> colors fenced code inside the buffer, and with `browser.highlighter = "nvim"`
> mdview reads those colors back out and paints the browser with them, so both
> sides show the same thing instead of two highlighters guessing the language
> separately. Blocks it does not paint fall through to highlight.js.
>
> **[documentation.nvim](https://github.com/StefanBartl/documentation.nvim)** —
> holds the ecosystem architecture this plugin is the presentation half of.
>
> Both companions are soft: mdview never loads them, and `:checkhealth mdview`
> only notes when they are present.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real plugin
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.9+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — notifications, autocommands, path handling and the command layer |
| `curl` | required — downloads the relay binary and the client bundle on first use |
| `tar` | required — extracts that bundle |

`:checkhealth mdview` treats either missing CLI tool as an error, not a
warning: without them there is nothing to run.

No language toolchain is required to *use* the plugin — Go, Rust and Node are
only needed to build it from source, which is
[docs/development.md](docs/development.md).

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| [markdown.nvim](https://github.com/StefanBartl/markdown.nvim) | The editing toolkit whose buffer edits mirror into the preview |
| [color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim) | The buffer's own fenced-code colors, painted into the browser |

`curl` is declared in [docs/install.json](docs/install.json) and read by
lib.nvim's
[deps module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup explains it the first time `setup()` runs after installing;
`:Lib deps show mdview.nvim` repeats it any time. Turn the popup off in this
plugin's own spec with `require("mdview").setup({ deps_popup = false })`, or
globally with `vim.g.lib_nvim_deps_disable_first_run = true`.

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/mdview.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  ft = { "markdown" },
  cmd = { "MDView" },
  opts = {},
}
```

`ft` plus `cmd`: the filetype trigger covers opening a document, and the
command trigger covers reaching for `:MDView` from somewhere else — including
the standalone preview, which does not need a Markdown buffer at all. Packer
and the eager-loading variants are in
[docs/installation.md](docs/installation.md).

---

## Quickstart

Open a Markdown file and start a session — the first run downloads the relay
binary and the client bundle, and nothing else is needed:

```vim
:MDView start
```

Then, once the tab is open:

```vim
:MDView cursor        " show the Neovim cursor in the preview
:MDView theme         " switch the preview theme
:MDView overlay       " mount a floating table of contents
:MDView pin           " hold the preview on this document
:MDView standalone    " hand it to the relay's own file watcher; survives :qa
:MDView stop
```

Verify your setup any time with:

```vim
:checkhealth mdview
```

---

## What you get with the defaults

| Command | Does |
| --- | --- |
| `:MDView start` / `stop` / `toggle` / `open` | Start, stop or re-open the live browser session |
| `:MDView standalone` | Preview via the relay's own file watcher — outlives `:qa`, no Neovim in the chain |
| `:MDView preview-tab` | The in-editor tab preview: no browser, no server |
| `:MDView cursor` | The Neovim cursor in the preview — line, caret, or section spotlight |
| `:MDView selection` | Mirror the visual selection into the preview, for presenting |
| `:MDView sync` | Pause or resume Neovim → browser scroll sync at runtime |
| `:MDView pin` | Hold the preview on one document while you move around other buffers |
| `:MDView zoom` | The preview's font-size scale, independent of the browser's |
| `:MDView overlay` | Mount or unmount a floating table of contents |
| `:MDView breadcrumbs` | The session outline of visited sections, exportable |
| `:MDView reveal` | Reveal or hide private fenced blocks |
| `:MDView blanklines` | Blank-line handling in the rendered output |
| `:MDView theme` | Switch the preview theme at runtime |
| `:MDView weblogs` / `log` / `file-log` / `diagnose` | Relay stdout, the internal log ring, the persistent relay log, and the full diagnostics report |

Without a command of their own: reverse scroll and click-to-navigate move the
Neovim cursor from the browser; link hover previews show a target inline; and
`sync_checkboxes` / `sync_fields` write task-list ticks and form-field edits
back into the source. The full surface is
[docs/commands.md](docs/commands.md).

**Most subcommands do two things at once.** `cursor`, `zoom`, `overlay`,
`reveal`, `sync`, `theme` and `blanklines` each write to the shared config
*and*, if a session is running, push a live update to the open tab. Running one
with no session up is never wasted — the choice survives into the next
`:MDView start`, and the command says which of the two just happened.

---

## Two previews, not one

`:MDView start` is the real thing: relay, WebSocket, WASM renderer, browser
tab, and every live control above.

`:MDView preview-tab` is a deliberately separate and much cheaper path — a
read-only mirror buffer in a Neovim tab, with no relay and no browser. The two
run on independent lifecycles, and none of the live-preview controls touch the
plain tab. If a control command seems to do nothing, check which of the two you
are looking at.

---

## Health check

```vim
:checkhealth mdview
```

Six sections: the environment, the installed assets, the configuration, the
running session, the optional companions, and the declared tools. The asset
section is the one to read after a failed first start — it says whether the
relay binary and the client bundle actually arrived.

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the
layout; [docs/architecture.md](docs/architecture.md) says which component is
written in which language and how they talk, and
[docs/development.md](docs/development.md) is the build and the four test
suites.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/mdview.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/mdview.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).

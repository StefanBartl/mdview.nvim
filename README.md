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
Buffer text is streamed to a browser tab and rendered client-side by a
Rust/WASM module with sanitization built in — no toolchain needed to run it.

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
> dependency — see [Requirements](docs/installation.md#requirements).

---

## Documentation

Start with the [documentation index](docs/README.md) — it lists every page and
says what each one answers.

**The Basics**

- [Requirements](docs/installation.md#requirements) — Neovim version, required plugins and CLI tools.
- [Installation](docs/installation.md) — plugin-manager variants, and where the relay binary and client bundle come from.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

**Reference**

- [Configuration](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) — every `:MDView` subcommand, including what ships with the defaults.
- [Bindings cheatsheet](docs/BINDINGS.md) — commands, autocommands and keymaps at a glance.
- [Workflow](docs/WORKFLOW.md) — once a session is running: which controls apply live, which need a restart, what breaks first.

**What it does**

- [Features](docs/FEATURES/README.md) — the full catalog, then per-theme depth: [preview](docs/FEATURES/PREVIEW.md), [rendering](docs/FEATURES/RENDERING.md), [operations](docs/FEATURES/OPERATIONS.md), [security](docs/FEATURES/SECURITY.md), and [the machinery underneath](docs/FEATURES/MACHINERY.md).
- [Standalone](docs/standalone.md) — a preview that outlives `:qa`, or runs with no Neovim at all.
- [Companion plugins](docs/companion-plugins.md) — which optional plugins pair with the live preview, and what each adds.

**Under the hood**

- [Architecture](docs/architecture.md) — which component is written in which language, and how they talk.
- [Health check](docs/health.md) — what `:checkhealth mdview` reports, section by section.

**Working on it**

- [Contributing](docs/CONTRIBUTING.md) — ground rules, the four-language layout, and how to change a component.
- [Development](docs/development.md) — building from source and running the four test suites.
- [Relay testing](docs/relay-testing.md) — driving the Go relay's endpoints by hand to pin a failure to one hop.
- [Diff harness](docs/diff-harness.md) — benchmarking and verifying the experimental line-diff transport.
- [Ecosystem architecture](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/ECOSYSTEM.md) — how docs, static analysis and runtime split across `lib.nvim`, `documentation.nvim`, `runtime-analysis.nvim` and mdview.nvim.
- [Feedback](https://github.com/StefanBartl/mdview.nvim/issues) — bugs, feature requests and usage questions; broader discussion in [Discussions](https://github.com/StefanBartl/mdview.nvim/discussions).

`:help mdview` is the same reference inside the editor.

---

## License

MIT — see [LICENSE](LICENSE).

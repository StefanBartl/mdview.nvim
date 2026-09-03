# mdview.nvim — Documentation

Everything written down about mdview.nvim, and what each page is for.
The [repository README](../README.md) is the short version; this is the index.

## Start here

| Page | What it answers |
|---|---|
| [installation.md](installation.md) | How do I install it, what does it need, and where do the relay binary and client bundle come from? |
| [WORKFLOW.md](WORKFLOW.md) | Once a session is running, how do the pieces combine — which controls apply live, which need a restart, what breaks first? |
| [FEATURES/](FEATURES/README.md) | What can it actually do? |

## Reference

| Page | What it answers |
|---|---|
| [commands.md](commands.md) | What does each `:MDView` subcommand do? |
| [configuration.md](configuration.md) | Which `setup()` options exist, and what are their defaults? |
| [BINDINGS.md](BINDINGS.md) | Commands, autocommands and keymaps at a glance, with the full argument shape of each. |
| [standalone.md](standalone.md) | How do I get a preview that outlives `:qa`, or runs with no Neovim at all? |
| [companion-plugins.md](companion-plugins.md) | Which optional plugins pair with the live preview, and what does each add? |

## Under the hood

| Page | What it answers |
|---|---|
| [architecture.md](architecture.md) | Which component is written in which language, and how do they talk? |
| [FEATURES/MACHINERY.md](FEATURES/MACHINERY.md) | The parts with no command of their own — caches, throttling, the diff transport, lifecycle. |
| [development.md](development.md) | How do I build mdview.nvim from source and run its four test suites? |
| [relay-testing.md](relay-testing.md) | How do I drive the Go relay's endpoints by hand to pin a failure to one hop? |
| [diff-harness.md](diff-harness.md) | How do I benchmark and verify the experimental line-diff transport? |
| [install.json](install.json) | The declared external tools (`curl`), read by `lib.nvim.deps` and `:checkhealth mdview`. |

## Not in this repository

[Ecosystem architecture](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/ECOSYSTEM.md)
— where docs, static analysis and runtime each belong across the four pieces
mdview.nvim is the presentation half of (`lib.nvim`, `documentation.nvim`,
`runtime-analysis.nvim`, mdview.nvim), and why telemetry reports render through
here rather than growing their own viewer.

## Two things worth knowing once

**Two previews, not one.** `:MDView start` is the real thing — relay,
WebSocket, WASM renderer, browser tab, and every live control.
`:MDView preview-tab` is a deliberately separate, much cheaper path: a
read-only mirror buffer in a Neovim tab, with no relay and no browser. They run
on independent lifecycles and none of the live-preview controls touch the
plain tab. If a control command seems to do nothing, check which of the two you
are looking at.

**Most `:MDView` subcommands do two things at once.** `cursor`, `zoom`,
`overlay`, `reveal`, `sync`, `theme` and `blanklines` each write to the shared
config *and*, if a session is running, push a live update to the open tab. So
running one with no session up is never wasted — the choice survives into the
next `:MDView start`. The command says which of the two just happened.

# Installation

## Requirements

| | Needed for | Notes |
|---|---|---|
| Neovim 0.9+ | everything | |
| [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) | everything | declare it as a dependency, see below |
| `curl` | first `:MDView start` | downloads the relay binary + client bundle from GitHub Releases |
| `tar` | first `:MDView start` | extracts the client bundle (ships with Windows 10+, macOS, Linux) |
| a browser | viewing the preview | |

No Go, Rust or Node toolchain is needed to *run* mdview — that is only for
[building from source](development.md).

## How the runtime pieces get there

`:MDView start` spawns a native relay binary and serves a prebuilt browser
client (HTML/JS/WASM) from a directory. Neither is committed to the repository,
so cloning the plugin alone does not produce them. On the first `:MDView start`
for a given `install.version`, mdview downloads and checksum-verifies both from
GitHub Releases into `stdpath("data")/mdview/bin/<version>/` and reuses them
from then on. Check what is present with `:checkhealth mdview`.

## Installation variants

| Variant | You need | `setup()` | Use when |
|---|---|---|---|
| **A — Release (recommended)** | nothing but `curl`/`tar` | no `dev`/`standalone` keys | normal use, including a local clone you only edit Lua in |
| **B — locally built relay** | Go 1.22+ | `dev.binary_path` (+ `standalone.binary_path`) | you changed Go code, or need relay features newer than the pinned release |
| **C — full source build** | Go + Rust + `wasm-pack` + Node 18+ | `dev.binary_path` **and** `dev.web_root` | you changed the client (TS) or the WASM renderer (Rust) |

Variants B and C are described step by step in
[Development](development.md#build-variants). Two traps worth knowing before
you set them:

- Setting `dev.binary_path`/`dev.web_root` **disables** the automatic download
  for that piece. If the path does not exist, `:MDView start` fails with
  `dev.binary_path is not executable: ...` — it does not fall back to the
  release.
- On Windows, `npm run build:go` produces `native/server/mdview-server`
  **without** a `.exe` suffix. Point `binary_path` at that exact name.

**When to use which loading strategy:**

| Variant | Startup impact | Commands available | When to use |
|---|---|---|---|
| **`ft`/`cmd` (Recommended)** | Minimal | On `:MDView` or when opening a markdown file | Default — true lazy-loading |
| **`lazy = false`** | Loads immediately | Right from the start | Only if you want the plugin fully initialized before any command |

## lazy.nvim

*Lazy-load on markdown files or the plugin's own commands (recommended):*
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

## packer

```lua
use {
  "StefanBartl/mdview.nvim",
  requires = { "StefanBartl/lib.nvim" },
  ft = { "markdown" },
  cmd = { "MDView" },
  config = function()
    require("mdview").setup()
  end,
}
```

## Verifying the installation

```vim
:checkhealth mdview
```

Reports whether `curl` is available, whether the relay binary and client bundle
for the pinned `install.version` are cached, and where. Then open a markdown
file and run `:MDView start`.

No external toolchain is required to run the plugin — see [Development](development.md) only if you want to build mdview.nvim itself from source.

# Installation

**When to use which:**

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

No external toolchain is required to run the plugin — see [Development](development.md) only if you want to build mdview.nvim itself from source.

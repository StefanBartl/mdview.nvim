# Commands

mdview.nvim registers a single `:MDView <subcommand>` command (built via
[`lib.nvim.usercmd.composer`](https://github.com/StefanBartl/lib.nvim)), with
`<Tab>` completion for every subcommand and typed argument below.

| Command | Description |
| --- | --- |
| `:MDView start [file] [cwd=…]` | Start the relay and open the preview for the current buffer (or the given file). |
| `:MDView stop` | Stop the relay, detach autocommands, and (in isolated mode) close the browser. |
| `:MDView toggle [file] [cwd=…]` | Start if stopped, stop if running. |
| `:MDView open` | Re-open a browser tab against the already-running session (does not start a new relay). |
| `:MDView theme [name]` | Switch the preview theme at runtime (`github` \| `dark-dimmed` \| `plain` \| `tokyonight` \| `catppuccin`, optionally `-light`/`-dark`); no argument reports the current theme. |
| `:MDView preview-tab` | Toggle the in-Neovim tab preview (works standalone, no server needed). |
| `:MDView weblogs` | Show the relay's captured stdout, including `[client]` browser-side diagnostics. |
| `:MDView log [trace\|debug\|info\|warn\|error]` | Show mdview's internal log ring, optionally filtered to a level and above. |
| `:MDView log export [path]` | Export the internal log ring to a file. |
| `:MDView file-log` | Toggle persistent file logging of the relay's stdout, then report the state. |
| `:MDView file-log on [path]` | Enable persistent file logging (optionally set its path). |
| `:MDView file-log off` | Disable persistent file logging. |
| `:MDView file-log status` | Report persistent file logging state without changing anything. |
| `:MDView file-log path [value]` | Set the file log path (`value` is a path or `default`); omit `value` to report the current path. |
| `:MDView diagnose [path]` | Write a full component-state diagnostics report to a file and open it. |

File logging is opt-in and off by default — nothing is written to disk until
you run `:MDView file-log on`.

Run `:checkhealth mdview` to verify dependencies (lib.nvim, curl, tar) and
whether the relay binary and client bundle are cached.

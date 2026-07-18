# Commands

| Command | Description |
| --- | --- |
| `:MDViewStart [file] [cwd=…]` | Start the relay and open the preview for the current buffer (or the given file). |
| `:MDViewStop` | Stop the relay, detach autocommands, and (in isolated mode) close the browser. |
| `:MDViewToggle [file] [cwd=…]` | Start if stopped, stop if running. |
| `:MDViewOpen` | Re-open a browser tab against the already-running session (does not start a new relay). |
| `:MDViewTheme [name]` | Switch the preview theme at runtime (`github` \| `dark-dimmed` \| `plain` \| `tokyonight` \| `catppuccin`, optionally `-light`/`-dark`); no argument reports the current theme. |
| `:MDViewPreviewTab` | Toggle the in-Neovim tab preview (works standalone, no server needed). |
| `:MDViewShowWebLogs` | Show the relay's captured stdout, including `[client]` browser-side diagnostics. |
| `:MDViewLog [level\|export [path]]` | Show mdview's internal log ring (optionally filtered to `trace`/`debug`/`info`/`warn`/`error`), or `export` it to a file. |
| `:MDViewFileLog [on\|off\|toggle\|status\|path [<path>]]` | Toggle persistent file logging of the relay's stdout. Off by default — nothing is written to disk until you turn it on. `on <path>` / `path <path>` set the destination (also configurable as `file_log_path`); `path default` restores the default. |
| `:MDViewDiagnose [path]` | Write a full component-state diagnostics report to a file and open it. |

Run `:checkhealth mdview` to verify dependencies (lib.nvim, curl, tar) and whether the relay binary and client bundle are cached.

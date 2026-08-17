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
| `:MDView standalone [file] [--no-browser]` | Preview via the relay's own file watcher, with no Neovim in the chain — outlives `:qa` (file on disk only; needs a relay with `--watch`, v0.3.0+). See [standalone.md](standalone.md). |
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
| `:MDView cursor [line\|caret\|section\|off\|toggle]` | Set/toggle how the Neovim cursor is marked in the preview; no argument reports the current mode. See [PREVIEW.md](FEATURES/PREVIEW.md#neovim-cursor-marker). |
| `:MDView sync [pause\|resume\|toggle]` | Pause/resume Neovim → browser scroll sync (and the cursor marker) without tearing down the session. See [PREVIEW.md](FEATURES/PREVIEW.md#scroll-sync-pauseresume). |
| `:MDView zoom [+\|-\|reset\|<factor>]` | Adjust the preview's font-size scale; no argument reports the current zoom. See [PREVIEW.md](FEATURES/PREVIEW.md#preview-zoom). |
| `:MDView overlay <name> [on\|off\|toggle]` / `:MDView overlay list` | Mount/unmount a named overlay on the preview, or list known overlays and their state. See [PREVIEW.md](FEATURES/PREVIEW.md#overlays-floating-table-of-contents). |
| `:MDView breadcrumbs` / `breadcrumbs export [path]` / `breadcrumbs clear` | Report, export, or clear the session's visited-section outline. See [PREVIEW.md](FEATURES/PREVIEW.md#breadcrumbs-session-outline). |
| `:MDView reveal [on\|off\|toggle]` | Reveal/hide private (fenced) blocks in the preview; no argument toggles. See [RENDERING.md](FEATURES/RENDERING.md#private-blocks). |
| `:MDView blanklines [on\|off\|toggle]` | Toggle blank-line handling in rendered output. See [RENDERING.md](FEATURES/RENDERING.md#blank-line-handling). |

File logging is opt-in and off by default — nothing is written to disk until
you run `:MDView file-log on`.

`:MDView standalone` starts a preview that survives closing this Neovim: the
relay watches the file on disk itself, with no Neovim in the chain. It previews
the file as saved (no unsaved-buffer push, no scroll sync).
[standalone.md](standalone.md) covers it and the `scripts/mdview-bg.*` terminal
wrappers.

Run `:checkhealth mdview` to verify dependencies (lib.nvim, curl, tar) and
whether the relay binary and client bundle are cached.

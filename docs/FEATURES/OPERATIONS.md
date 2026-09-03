# Operations

Everything for running and debugging a session day to day: getting the
native assets onto disk in the first place, `:checkhealth`, and the
different logs/diagnostics available once something needs explaining.

## No-toolchain install from GitHub Releases

The relay binary (`mdview-server`, Go) and the browser client bundle
(`mdview-client.tar.gz`: HTML/JS + the Rust/WASM renderer) are prebuilt,
checksum-verified downloads from GitHub Releases, fetched once per pinned
version on first use — the same bootstrap pattern as mason.nvim/
nvim-treesitter. No Go, Rust, or Node toolchain is required on the end
user's machine; `curl` and `tar` are the only external tools needed. The
platform/arch triplet (`windows|darwin|linux` × `amd64|arm64`) is detected
automatically, and downloads land in a version-scoped directory
(`stdpath("data")/mdview/bin/<version>`) so upgrading the plugin's pinned
`install.version` doesn't reuse a stale binary. A `checksums.txt`
(goreleaser-style) fetched alongside the assets is what the checksum
verification is checked against — a corrupt or tampered download fails
closed rather than being silently accepted.

- **Module:** `lua/mdview/adapter/install.lua` (`ensure_asset`, `status`), `lua/mdview/config/init.lua` (`install.repo`, `install.version`)
- **Config:** `install.repo` (fork override), `install.version` (pins which release ships)

## `:checkhealth mdview`

One check covering every layer that can go wrong independently: Neovim
version, the `lib.nvim` hard dependency (probed via a representative
submodule so a half-installed `lib.nvim` is also caught, not just a missing
one), `curl`/`tar` availability, whether the relay binary and client bundle
are already cached (and, for the bundle, whether the cache actually looks
complete — `index.html` + a `.wasm` under `assets/`, since an interrupted
extract fails silently at render time with a blank page rather than an
error), the resolved config (`open_mode`, `theme`, `scroll_sync`,
`open_preview_tab`, which `experimental.*` flags are on), browser
resolution for `open_mode = "isolated"`, whether a session is currently
running (and if so, whether `GET /health` on the relay actually returns
`ok`), and optional companion-plugin detection (`markdown.nvim`,
`color_my_ascii.nvim` — neither required, both just noted if present).

- **Module:** `lua/mdview/health.lua`

## `lib.nvim` as a required runtime dependency

Unlike the companion plugins above, `lib.nvim` is a **hard** dependency,
not optional — mdview.nvim uses it for cross-platform path/OS helpers
(`is_windows`, separators), the `:MDView` compound-usercommand
infrastructure (`lib.nvim.bindings.usercmd.composer`), and structured logging.
`:checkhealth mdview` errors (not warns) if it's missing.

- **Module:** referenced throughout `lua/mdview/` — see `lua/mdview/health.lua` for the representative probe

## Plugin log (`:MDView log`)

The plugin's own internal structured log ring (built on `lib.nvim.logger`)
— launcher, live-push, `ws_client`, and the rest of the Lua-side machinery.
Distinct from `:MDView weblogs` (the *relay's* stdout, including
`[client]`-prefixed browser diagnostics forwarded from the WASM/JS side)
and from `:MDView breadcrumbs` (a human-facing session outline, see
[PREVIEW.md](PREVIEW.md#breadcrumbs-session-outline)) — three different
logs for three different halves of the system.

- **Module:** `lua/mdview/bindings/usrcmds/log.lua`, `lua/mdview/log.lua`
- **Usercmds:** `:MDView log [level]` (level filters to that level and above: trace/debug/info/warn/error), `:MDView log export [path]`

## Persistent relay log (`:MDView file-log`)

Opt-in, off by default — a plain `:MDView start` never writes anything to
disk. Once enabled, the relay's stdout capture is additionally persisted to
a file (default `stdpath("log")/mdview/relay-<timestamp>.log`, never a
`logs/` directory relative to the current working directory). Toggled and
inspected independently of whether it's currently on:

- **Module:** `lua/mdview/bindings/usrcmds/file_log.lua`, `lua/mdview/adapter/log.lua`
- **Usercmds:** `:MDView file-log` (toggle), `:MDView file-log on|off [path]`, `:MDView file-log path <path|default>`, `:MDView file-log status`
- **Config:** `file_log` (default `false`), `file_log_path` (default unset — see the built-in default above)

## Relay stdout viewer (`:MDView weblogs`)

Shows the relay process's own stdout — including `[client]`-tagged lines
forwarded from browser-side diagnostics — in a scratch buffer. The
lowest-level view available short of reading `file-log`'s persisted output
directly.

- **Module:** `lua/mdview/bindings/usrcmds/show_weblogs.lua`, `lua/mdview/adapter/log.lua`
- **Usercmds:** `:MDView weblogs`

## Full diagnostics report (`:MDView diagnose`)

Writes a single report file capturing the state of every component (config,
install status, session state, and the rest of what `:checkhealth` reports
piecemeal) and opens it immediately in a new tab — meant to be copy/pasted
whole when handing off a bug report, rather than reconstructing the picture
from several separate commands.

- **Module:** `lua/mdview/bindings/usrcmds/diagnose.lua`, `lua/mdview/diagnostics.lua`
- **Usercmds:** `:MDView diagnose [path]`

Standalone-mode lifecycle (`:MDView standalone`, its background/terminal
launcher scripts) is a preview-architecture concern and lives in
[PREVIEW.md](PREVIEW.md#standalone-preview-outlives-neovim) rather than
here, to avoid documenting the same command in two places.

## Multi-language project layout

Four components across four languages, relevant when a bug report needs to
be routed to the right layer: `lua/mdview/` (the Neovim-side plugin), `native/
server/` (the Go relay + its internal packages, `main.go`), `native/
wasm-render/` (the Rust crate compiled to WASM — comrak + ammonia, see
[RENDERING.md](RENDERING.md)), and `src/client/` (the TypeScript/Vite
browser bundle that loads the WASM module and drives the preview page — see
`src/client/vite.config.ts`, `src/client/main.ts`). `dist/` and `doc/` at the repo
root are build output and Vimdoc respectively, not source.

- **Module:** `lua/mdview/` (Lua), `native/server/` (Go), `native/wasm-render/` (Rust/WASM), `src/client/` (TypeScript)
- **Docs:** [RENDERING.md](RENDERING.md) for the WASM half, [`../../src/client/vite.config.ts`](../../src/client/vite.config.ts) for the bundle

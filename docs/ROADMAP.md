# mdview.nvim — Roadmap

## Implemented

- Browser-based live Markdown preview: a Go relay streams raw buffer text
  over WebSocket, rendering/sanitizing happens client-side in a Rust/WASM
  module (comrak + ammonia) — no server-side rendering step
- No Node/Go/Rust toolchain required to run it: relay binary and client
  bundle are downloaded once from GitHub Releases (`mdview.adapter.install`)
- `:MDView <subcommand>` compound usercommand (via `lib.nvim.usercmd.composer`)
  with `<Tab>` completion — start/stop/toggle/open/theme/weblogs/log/
  file-log/diagnose/preview-tab and the live-preview controls (cursor/sync/
  zoom/reveal/overlay/breadcrumbs); see [BINDINGS.md](BINDINGS.md)
- Live preview controls without reload: cursor marker (line/caret/section),
  scroll sync (nvim → browser, throttled), zoom, private-block reveal,
  overlays (table of contents), breadcrumbs
- Throttled `TextChanged`/`TextChangedI` live-push (`live_push_throttle_ms`,
  trailing-timer coalescing) — halved CPU cost under sustained typing versus
  the unthrottled baseline (see `docs/Roadmap/Roadmap.md` benchmark)
- `preview-tab`: a fully decoupled, no-browser/no-relay Neovim-tab Markdown
  mirror (Treesitter-highlighted, falls back to `syntax=markdown`)
- `standalone` background preview that outlives the Neovim session that
  started it (see [standalone.md](standalone.md))
- Local image asset serving so relative `<img>` targets resolve against the
  viewed document's directory, not the client bundle
- Loopback-only relay with per-session token + Origin checks
- `:checkhealth mdview` (curl/tar availability, install cache, lib.nvim
  presence, companion-plugin detection)
- Cross-platform browser autodetection/launch (Windows/macOS/Linux), with a
  Windows focus-preserving PowerShell path for `focus = "nvim"`
- `lib.nvim` as a required runtime dependency (usercommands, cross-platform
  path helpers, structured logging)

---

## Checklist audit (2026-08-09)

mdview.nvim went through the personal Lua/Neovim checklist pass
(`PERFORMANCE.md`, `LUA_NVIM.md`, `REVIEW.md`, `RELEASE.md`,
`Refactoring..md`). Summary of what was found and fixed:

- Added `stylua.toml` (tabs, matching the codebase's existing indentation)
  and a `stylua` CI job — the format-check gap was previously invisible
  since only `luacheck` ran in CI. Reformatted the ~35 files that had
  drifted from the rest of the tree's tab-indented style.
- Removed the two remaining license references (`LICENSE`, `package.json`'s
  `"license"` field) per this project's no-license-file convention.
- `lua/mdview/adapter/runner.lua`: two synchronous-path `notify()` calls
  (invalid spawn command, failed to spawn) were pure duplication of the
  caller's own error reporting (`bindings/usrcmds/start/server/launcher.lua`
  already notifies when `start_server()` returns `nil`) — replaced with
  `log.append()`, matching the "fail late" / report-at-the-boundary
  refactor pattern already used in `core/state.lua`. The remaining
  `notify()` calls inside async pipe/exit callbacks were kept: those fire
  after the original synchronous caller has already returned control to the
  event loop, so there is no boundary to bubble the error to.
- `---@param cb fun(...)`-style annotations were audited across the tree
  (the exact bare-type-without-name bug found earlier in `pickers.nvim`) —
  all instances already name their parameter correctly; no fix needed.
- `.luarc.json` already present with `diagnostics.globals = ["vim"]`.
- Created this file (`docs/ROADMAP.md`) — previously the only roadmap doc
  was `docs/Roadmap/Roadmap.md`, a detailed German engineering log kept for
  history/bug-postmortems; it remains as-is and is linked from here rather
  than replaced.

Full change history and bug postmortems: [`docs/Roadmap/Roadmap.md`](Roadmap/Roadmap.md).

## Not planned

- `:MDView detach` was removed (see `docs/Roadmap/Roadmap.md`, BUGS #8–10)
  in favor of `:MDView standalone`, which dominates it on every axis that
  was evaluated.

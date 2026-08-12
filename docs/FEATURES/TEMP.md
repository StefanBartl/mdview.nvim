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

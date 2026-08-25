# mdview.nvim — log of completed items

> **Open tasks:** [`ROADMAP.md`](ROADMAP.md) · **Ideas with no near-term
> implementation:** [`IDEAS/`](IDEAS/) · **Feature catalogue:**
> [`../FEATURES/`](../FEATURES/)
>
> This file is the **decision log**: what was built, why it was built that
> way, what the trade-off behind it was. It does not replace
> [`../FEATURES/FEATURES.md`](../FEATURES/FEATURES.md) — that one says *what*
> exists today; this one says *why* it turned out this way.
>
> Pre-rewrite documents under [`history/`](history/) carry an OUTDATED banner
> and are history only.

## BUGS

  1. ~~health module: `require("mdview.health").check()` was missing~~ — fixed.
     Cause: `lua/mdview/health.lua` only exported `health_report`, not `check()`;
     a better `check()` implementation sat unused in `plugin/health.lua`
     (wrong path, never loaded by `:checkhealth`). Now merged into
     `lua/mdview/health.lua` and adapted to the native Go/Rust architecture
     (checks curl/tar instead of Node/npm).

  2. ~~Use the current browser session instead of a "TempApp" browser~~ — fixed:
     `build_args_for_browser.lua`'s profile directory was a fresh `fn.tempname()`
     on every call — every `:MDViewStart` created a completely new, isolated
     browser process instead of reusing the running mdview session. Now a fixed,
     persistent path under `stdpath("data")/mdview/browser-profile`, reused
     across calls (with the same profile, Chrome/Firefox normally open a new tab
     in the existing window rather than a new process). It stays isolated from
     the user's real default browser profile — only the "throwaway session on
     every single call" behaviour is fixed.
  3. Clarify: shouldn't we use WebSocketStream? — No: WebSocketStream (the
     Streams API over WebSocket, backpressure-capable reading) pays off for very
     high throughput or large binary payloads. mdview.nvim transmits small text
     updates (one markdown buffer) per broadcast — the existing simple
     `ws.send`/`onmessage` path (Go: `gorilla`-style WS via `nhooyr.io/websocket`,
     client: native `WebSocket`) is sufficient here and considerably easier to
     debug. Not pursued.
  4. ~~`:MDViewStop` deleted itself and `:MDViewOpen`~~ — fixed, critical bug.
     `stop.lua`'s `M.stop()` called `usercmds_registry.detach_all()`; `:MDViewOpen`
     and `:MDViewStop` were registered as "non-persistent" through that registry
     (`bindings/usrcmds/init.lua`'s `attach_non_persistent()`), but nothing ever
     re-registered them. After the first `:MDViewStop` both commands were gone
     for the rest of the Neovim session. Fix: all four user commands are now
     "persistent" (registered once at `setup()`, never torn down — autocommands
     still have a real attach/detach lifecycle, user commands do not).
     `usercmds_registry.lua` was thereby entirely unused, and deleted.

  5. ~~`:MDViewStart` started the server, but nothing happened afterwards: no browser, no
     initial push, and every buffer change only spammed "server ready after X ms, attempt 1"~~ —
     fixed, a chain of five bugs (verified by an E2E test against the real binary):
     - **`ws_client.wait_ready` never called `cb(true)` on success** — only an echo.
       The entire on-ready block in the launcher (initial push + browser open) and every
       live push therefore ran into the void; the echo per keystroke was the whole effect.
       Fix: `cb(true)` plus a readiness cache (`M._ready`, no more curl /health per
       keystroke; reset via `reset_ready()` on stop/respawn).
     - **The launcher's on-ready crashed at `live_push.attach()` without a group**
       ("Invalid 'group': 0") — directly BEFORE the initial push and the browser open;
       it only became reachable at all through the cb fix. Fix: redundant call removed
       (autocommands are already registered at spawn) plus `live_push.attach(nil)`
       hardened (no more `group or 0`).
     - **Token mismatch**: `launcher.start` called `server_args.resolve()` again (rotating
       the session token in state), while `runner.start_server` returned the EXISTING
       process (with the old token) → all /update and /ws requests ran as silent
       403s (curl exits 0 on HTTP errors). Fix: a running process is reused, and
       resolve/token rotation happens only on an actual spawn.
     - **`state.proc_is_running()` checked the nonexistent field `M.proc`** instead of
       `M.runner.proc` → always false. Fix: correct field plus handle validity.
     - **`resolve_browser_url` preferred `browser.dev_server_port` (43220, Vite)
       unconditionally** — in production nothing listens there; even a browser that did
       open would have pointed into the void. Fix: the real backend port
       (`vim.g.mdview_server_port`); the dev port only through `vim.g.mdview_dev_port`
       (which is set exclusively when the runner has parsed a real Vite line from stdout).
       `browser.dev_server_port` removed as a config field.
     Also: debug defaults (`debug`, `debug_plugin`, `debug_preview`) from true to false —
     server stdout echoes and per-push notifications are now opt-in instead of constant spam.

  6. ~~After the fix above: `:MDViewStart` → `:MDViewStop` → `:MDViewStart` crashed with
     "Invalid 'group': 216", and after that every further `:MDViewStart` only said
     "server already running" without a browser~~ — fixed, three follow-on bugs:
     - **`autocmds.teardown()` deleted the augroup by id, but `lib.nvim`'s `get_augroup`
       caches that id** and handed it back on restart — now a deleted, invalid id →
       `nvim_create_autocmd` crashed (`bufenter.lua`). Fix:
       `autocmds.init` creates the augroup directly via `nvim_create_augroup(name, {clear=true})`
       (always valid, no stale cache); the redundant `_attached_groups` dedup in
       `live_push` removed.
     - **Half-state after the crash**: `state.set_server(proc)` ran BEFORE `autocmds.attach()`,
       which then crashed → `server` stayed set → "already running" against a session that
       never finished starting. Fix: `set_server` only after a successful `attach`.
     - **`:MDViewStart` with a running server did nothing useful** (only "already running").
       The most common reason for another `:MDViewStart` is, however, a closed browser window.
       Fix: the "already running" branch now reopens the preview surface
       (`mdview.open()` or the tab preview) instead of merely complaining.
  7. ~~Chrome opened a "strange" window with no taskbar icon and no toolbar~~ —
     `--app=` mode was to blame (a chromeless app window). Fix: `build_args_for_browser`
     now uses `--new-window` → a normal browser window (taskbar icon, address bar).
     The isolated profile stays — it is exactly what makes `stop_on_browser_exit`/
     `browser_autoclose` reliable (a start into the user's already running browser would
     fork and exit immediately, and closing would not be detectable).
  > **RESOLVED (2026-07-26) for #8–#10: `:MDView detach` was removed.** All three bugs
  > were symptoms of the same underlying problem — a detached, headless, stdio-less
  > nvim is a poor long-term host: an input-poll-driven loop (→ #8 timing), no
  > file watch and no `--listen` (→ #9 no live push, a static snapshot), no tab-close
  > observer (→ #10). Since the detached instance is also never edited in, the claimed
  > live-buffer advantage does not in fact exist → `detach` was completely dominated by
  > `:MDView standalone`. Consequence: `detach`, `detach.lua` and the
  > `User MDViewSessionEnded` event removed; the terminal wrappers (`mdview-bg.*`) now
  > fire `:MDView standalone`. The analysis below stands as the rationale. See
  > `docs/Roadmap/KONZEPT_headless_und_standalone.md` and `docs/standalone.md`.

  8. **`:MDView detach` / `scripts/mdview-bg.ps1`: the browser tab does not open at all, or
     only after a delay of several minutes** (observed under Windows), even though the relay
     itself comes up cleanly (health check ok, initial push arrives). ~~Still open~~ — the next
     point of attack when picking this up again:
     - The difference to `:MDView standalone` (which opens reliably and immediately): there,
       the browser open runs directly inside the Go relay binary (`native/server/open.go`, a
       single `rundll32.exe url.dll,FileProtocolHandler` call, no Neovim involved). `detach`
       and `mdview-bg.ps1` both run through a **headless, completely stdio-less, detached**
       Neovim instance (`nvim --headless -u scripts/minimal_init.lua -c "MDView start"`), in
       which both the `/health` poll (`ws_client.lua`'s `http_get`, curl via
       `vim.fn.jobstart`, every 200 ms for up to 10 s) and the actual open
       (`mdview.adapter.browser`'s `open_default`, likewise `vim.fn.jobstart`) run chained
       through Neovim's job control instead of through a single direct process spawn.
     - Reproducing the exact `detached.spawn` call by hand (`uv.spawn` with
       `stdio = {nil,nil,nil}`, `detached = true`) did work in one test run
       (health check, WebSocket connect and render all came through) — so the code is not
       fundamentally wrong, the timing is merely unreliable.
     - Suspicion: `vim.fn.jobstart()` calls from a headless and detached (no stdio,
       no console) Neovim instance on Windows are, under certain conditions, markedly
       slower than from a normal interactive instance — and `detach`/`mdview-bg.ps1`
       chain three of them (health poll → initial push → browser open) instead of getting
       by with a single native spawn the way `standalone` does. Not yet isolated to an exact
       cause (observed that way on the original test machine, not reproduced in another
       environment — so more likely Neovim job control/Windows specific than a logic error
       in the plugin code itself).
     - Possible fix, should that be confirmed: spawn the browser-open step in the `detach`
       path natively and directly, just as `standalone` does (e.g. through a small Go helper
       or a direct `uv.spawn` call from Lua), instead of through `vim.fn.jobstart` from
       inside the headless instance.
  9. **`:MDView detach`: live push and scroll sync do not reach the detached preview when the
     file is edited from a separate/new Neovim instance** — verified by test (README.md edited
     and saved from a second, independent headless nvim instance; no new activity whatsoever
     arrived in the detached session's relay log afterwards). Cause: the detached instance
     holds its own buffer state as of the spawn moment; there is no file watcher (no
     `vim.loop.new_fs_event`, no `checktime`/`autoread` timer — checked, none of that exists
     in the code) and `detach.lua` starts the child process without `--listen`, so one cannot
     attach to that particular instance afterwards via `nvim --server`/`--remote` in order to
     go on writing "inside it" either. That means the core difference to `standalone` described
     in the module documentation (`bindings/usrcmds/detach.lua`) ("live buffer push … because a
     real Neovim drives it") does not in fact hold in the only usage pattern currently reachable
     (editing the file externally). Possible fix: give `detach.lua` a
     `--listen` socket (print the address in the start notification) so one can reattach via
     `nvim --server <addr> --remote` — or add a file watcher that rereads and pushes on an
     external change.
  10. **`:MDView detach`: closing the preview tab does NOT end the detached Neovim instance
      by itself**, even though the start notification promises exactly that ("stop it by closing
      the preview tab, or kill the pid"). Verified by code analysis: `User MDViewSessionEnded`
      is fired in the entire code base at exactly one place (`bindings/usrcmds/stop.lua`,
      inside `:MDViewStop`) — nothing observes a tab close and fires the event
      automatically. The default `browser.open_mode` ("default", not overridden by
      `minimal_init.lua`) explicitly yields, per `adapter/browser/init.lua`, "a handle with no
      job_id: mdview can't programmatically close it" — `on_exit`/`stop_on_browser_exit`
      are no-ops there. And even if one wanted to trigger `:MDViewStop` manually: the
      detached instance has no `--listen` socket, so it cannot be reached from outside at all.
      Conclusion: at present the only working way to end a `:MDView detach` instance really is
      `Stop-Process`/`taskkill` on the PID — the "close the tab" part of the notification
      message is currently misleading. Related to point 9 (`--listen` would be the
      precondition for a clean fix here too, e.g. via a periodic health poll against the relay:
      when no clients are connected any more, trigger `:MDViewStop` itself).
  11. ~~`:MDView start` (the normal, non-standalone/detach path) had no way to use a
      locally built relay/client version~~ — fixed. `server_args.resolve()` used to
      always call `install.ensure_binary()`/`install.ensure_client_bundle()` (a fixed
      binding to `install.version`, default `v0.2.0`); there was **no** override, neither as
      a config field nor as an env var — even though exactly that had already been described
      in an earlier documentation note as `dev = { binary_path, web_root }` (a field that
      existed nowhere in the code). Since `install.version`'s pin is older than the `/control`
      route (overlay/zoom/cursor live control), those live commands ran into the void over the
      normal start path — a fire-and-forget POST against a route the pinned release binary does
      not know yet, without an error or an effect. Fix: new `dev.binary_path` / `dev.web_root`
      (with a fallback to `$MDVIEW_DEV_BINARY` / `$MDVIEW_DEV_WEB_ROOT`, for the same reason as
      with `standalone` — a detached process loads no Lua config) in
      `lua/mdview/adapter/server_args.lua`; documented in `docs/configuration.md`. Verified
      end to end: locally built relay (current `main` branch) started via `:MDView start`,
      `/control` posted directly with zoom/overlay/cursor payloads → all three `204`.

  1. Resolve `TODO` comments
  3. ~~It has to be ensured that `npm` is installed and available on the path~~ — obsolete since the Go/Rust rewrite:
     end users no longer need npm/Node; `mdview.adapter.install` downloads the finished
     server binary plus client bundle from GitHub Releases. `:checkhealth` checks
     `curl`/`tar` instead.
  4. ~~Add a field open_on_start (default true) and open_url (overrides) to mdview.config.~~
     `browser.browser_autostart` already covers `open_on_start` (same semantics, existed
     already). Newly added: `browser.open_url` — a static override URL, taking effect in
     `launcher.resolve_browser_url()` after the per-call `opts.browser_url` and before the
     computed key/token URL.
  5. ~~In case one wants finer control: only open when vim.fn.has("gui_running") == 1 or
     vim.env.DISPLAY is set.~~ — fixed: `launcher.has_display()` (Windows/macOS always
     true, Unix checks `DISPLAY`/`WAYLAND_DISPLAY`), gated behind the new
     `browser.require_display` (default true). Without a display: a warning instead of a
     pointless browser spawn attempt.
  6. ~~In debug mode, optionally vim.notify("Opening browser: " .. url).~~ — fixed, `launcher.lua`
     now logs that before every `browser_adapter.open()` call (`log.debug`, gated on
     `debug_preview` like all the other debug logs).
  7. Focus after MDViewStart goes to the browser — presumably already the case (a new
     Chrome/Firefox `--app` window is normally focused by the OS automatically), but not
     reliably enforceable from within Neovim (no cross-platform API for it, short of
     fragile OS-specific hacks like `wmctrl`). Not pursued.
  8. Decided: what goes into the log file, what is printed in nvim? `adapter/log.lua`
     holds two independent sinks: an in-memory ring buffer (max. 2000 lines, visible via
     `:MDViewShowWebLogs`) and optionally a log file (only when `log.setup({file_path=...})`
     is set explicitly — not active by default). UI echo (`vim.api.nvim_echo`) only when
     `debug=true`.
  9. ~~How should the mdview-server process behave when nvim was closed without
     `MDViewStop` having been called?~~ — a real bug found and fixed: `vim_leave.lua`'s
     `VimLeavePre` autocommand was registered with `pattern = defaults.ft_pattern`.
     `VimLeavePre` is, however, a global lifecycle event, not a buffer event — Neovim matches
     `pattern` against the *currently focused* buffer at the moment of the event. If the last
     active buffer was not a markdown file, the cleanup logic NEVER fired and the
     mdview-server process was left orphaned. Fix: `pattern` removed — it now always fires.
     Verified (test: current buffer = a `.lua` file, the autocommand fires regardless).
  10. ~~It is extremely important that new tabs attach to the existing process where
     possible.~~ — already given by the architecture: the Go relay groups connections
     per document path (`Registry` in `native/server/internal/relay/registry.go`), not per
     tab or process. `:MDViewOpen` (see `mdview.open()`) always connects to the running
     session instead of starting a new server.
  11. ~~When one closes the browser, that has to be handled: ideally the app closes as
     well.~~ — fixed: new `browser.stop_on_browser_exit` (default true).
     `launcher.lua`'s `on_exit` callback now calls `require("mdview.bindings.usrcmds.stop").stop()`
     when the browser process ends (e.g. window/tab closed). `stop()`'s
     existing `state` guards make a double stop call (e.g. when `:MDViewStop` closes the
     browser itself and thereby triggers `on_exit` again) harmless.
  12. ~~Is it the case, or possible, that one server hosts several CWDs?~~ — yes, already given.
      The running relay process is not bound to a CWD or project root: rooms are keyed by
      absolute file path (`native/server/internal/relay/registry.go`), and the server itself
      never reads files from disk for the markdown content (that arrives by HTTP POST from
      Neovim) — only the static client bundle path (`--web-root`) is fixed, and independent
      of which file is currently displayed. A single running server can therefore serve
      markdown files from arbitrarily many unrelated directories at the same time, without a
      restart. `server_cwd`/`cwd=...` concerns only the working directory of the server
      *process* itself, not which files it can display.

-

## Clean & Nice Code

  1. every parameter has to be typed
  2. modularize heavily

## Testing

  1. Line diff: `tests\mdview\util\diff.md`

---

## Client

---

## Server

  1. ~~In the server's wss broadcast: try/catch per client before the client.send(payload)~~ — fixed in
     `native/server/internal/relay/registry.go`: `Registry.Broadcast` collects send errors per
     connection instead of aborting the fan-out loop (see `TestRegistry_BroadcastCollectsSendErrorsWithoutStoppingFanout`).
  2. ~~Local image links in the rendered HTML show broken icons~~ — fixed. The
     WASM renderer (`comrak`) had always produced correct `<img>` markup for
     `![alt](image.png)` (see `source_map_does_not_pollute_image_alt`
     in `native/wasm-render/src/lib.rs`), but the only `http.FileServer`
     pointed at `web_root` (the client bundle), never at the directory of
     the document currently being displayed — a relative image path next
     to it ran into the void server-side. New: `GET /asset?key=&path=&token=` in
     `native/server/main.go`, resolved relative to the directory that
     `handleDoc` records per session (`Registry.SetDocDir`/`DocDir`) —
     so the base comes exclusively from the trusted local Neovim
     process, never from the browser tab. Path-traversal protection
     (`filepath.Clean` plus a containment check) and an extension allowlist
     (image formats only) deliberately narrow the route down, instead of
     it being a generic file server. Client-side, `src/client/render/
     localImages.ts` (`resolveLocalImages`, called after every render,
     analogous to `markExternalLinks`) rewrites relative `<img src>` onto that
     route; `http(s)://` and `data:` sources are left untouched. From
     `images.nvim`'s `docs/ROADMAP/CROSS-PLUGIN.md` (the mdview.nvim entry).
     Tests: `main_test.go` (traversal/allowlist/token/session), `registry_test.go`
     (`SetDocDir`/`DocDir`), `TESTS/client/localImages.test.ts`.

---

## Cross-Platform audit (personal checklist item 4)

  Found and removed two dead modules with dangerous module-load-time side effects
  (executed unconditionally the instant anything `require`d them, with no caller
  opting in):
  - `lua/mdview/utils/ports/cleanup/{cross_os,simple}.lua` — force-killed (`Stop-Process
    -Force` / `kill -9`) *any* process listening on port 43219, unconditionally, at
    module load. Unreferenced anywhere; deleted. The Go relay's `FindFreePort` already
    handles port conflicts by picking the next free port instead of killing anything.
  - `lua/mdview/adapter/runner_showlogs.lua` — called `log.setup({ debug = true, ... })`
    at module load, forcing debug mode on globally for anyone who ever required it;
    also referenced a nonexistent `cfg.LOG_BUF_NAME` field. Unreferenced anywhere
    (superseded by `bindings/usrcmds/show_weblogs.lua`); deleted.

  Also fixed a real bug in `lua/mdview/adapter/log.lua`: `local cfg require(...)` was
  missing its `=`, so `cfg` was always `nil` and `debug`/`log_buffer_name` config
  overrides were silently ignored. Fixed, and switched to reading the config live
  instead of caching a stale snapshot at require-time (adapter.log loads before
  `setup()` runs).

## filetree.nvim cross-check

  Checked whether mdview.nvim has features worth extracting into `filetree.nvim`
  (per the personal plugin checklist). Nothing applicable found: mdview.nvim is a
  markdown preview tool with no file-tree/file-navigation surface of its own.

- In filetree.nvim one could consider user commands / keymaps that, when the cursor sits on a file node that is markdown, let one open that file via mdview straight from the file tree

## bonus features

  1. ~~Provide `open_preview_tab` so the output is shown in an nvim tab instead of in the
     browser~~ — implemented, deliberately decoupled entirely from the browser/WASM pipeline
     (no HTML, no relay/WebSocket, no external tool such as `glow`):
     - New `lua/mdview/adapter/preview_tab.lua`: opens its own tab with a read-only mirror
       buffer of the source buffer, highlighted via Neovim's markdown treesitter
       parser (falling back to Vim's bundled `syntax=markdown` if the parser is
       missing — never unhighlighted). Live sync through its own, self-contained
       autocommand group (`bindings/autocmds/preview_tab_sync.lua`), completely independent of
       the `:MDViewStart`/`:MDViewStop` lifecycle — it works on its own without a running server.
     - New command `:MDViewPreviewTab` (a toggle, works standalone).
     - New config field `open_preview_tab` (default false): when true, `:MDViewStart`
       opens the tab preview instead of the browser (the relay/WASM pipeline still runs
       in the background, and `:MDViewOpen` can open the browser later at any time).
     - Deliberately decided against `glow`/external renderers: no additional optional
       toolchain candidate, no subprocess execution for this feature — that fits the
       "minimal attack surface" goal of the rewrite better than another opt-in external tool.
     - Verified end to end (headless nvim: toggle open/close, treesitter highlighting,
       live sync on buffer change, correct cleanup on close).
  2. ~~Render a file at a given path with an optional cwd:
     `:MDViewStart C:/Users/bartl/test.md {cwd?}`~~ — fixed: `:MDViewStart` now accepts
     `nargs="*"` and parses a file path plus an optional `cwd=...` in any order.
  3. ~~Start a file with a manually set cwd: `:MDViewStart cwd="c:/Users/bartl/"`~~ —
     fixed, the same mechanism as above (`cwd=` without a file argument uses the current buffer).
  4. ~~Closing the browser tab should end MDView as well~~ — fixed, see BUGS #11
     (`browser.stop_on_browser_exit`).
  5. How do we handle MDViewOpen being run on several files? Introduce sessions? —
     already solved: every file gets its own WS "room" (key = normalized path) in the
     Go relay; `:MDViewOpen` opens a tab for the current file in exactly that room, without
     affecting other open files/tabs. No additional session management needed.
  6. ~~Bidirectional scrolling, but at minimum from nvim to browser~~ — the nvim-to-browser
     direction implemented (browser to nvim remains open, it was not required: "but at minimum …"):
     A new `POST /scroll?key=...&token=...` endpoint (Go) that distributes the cursor line plus
     total lines as `"<line>/<total>"` to the room members via `Registry.BroadcastEphemeral` —
     deliberately NOT via `Broadcast`, since that would overwrite `LastPayload` and seed newly
     joining tabs with the scroll position instead of the real document (tested:
     `TestRegistry_BroadcastEphemeralReachesRoomWithoutTouchingLastPayload`). Messages are tagged
     with an `\x01` prefix (not possible in typed markdown) so that the client can tell a
     content update from a scroll ping apart without introducing a JSON envelope.
     A new `bindings/autocmds/scroll_sync.lua` sends on `CursorMoved`/`CursorMovedI`, throttled
     (`scroll_sync_throttle_ms`, default 150 ms), gated behind `scroll_sync` (default true). The
     client scrolls proportionally (the `line/total` ratio), no source-line mapping needed in
     comrak — deliberately not a pixel-exact match, but a robust, simple first pass.
     A side finding while verifying: `#mdview-root` had no CSS at all and was therefore not
     scrollable (it merely grew with the content) — `index.html` got a minimal stylesheet
     (`height:100vh; overflow-y:auto`), without which `scrollTop` would have been fundamentally
     ineffective anyway. Verified end to end with a real browser (Playwright preview).
  2. ~~`:MDView blanklines [on|off|toggle]`: show blank lines in the source 1:1 as visible
     spacing in the preview, instead of CommonMark's standard behaviour (every run of
     blank lines is compressed to exactly one paragraph gap)~~ — implemented. No
     Rust/comrak change needed: `data-sourcepos="startLine:col-endLine:col"` is already
     emitted unconditionally on every top-level block (`native/wasm-render/src/lib.rs`,
     `options.render.sourcepos = true`), independent of the source-map parameter for the caret.
     New on the client side, `src/client/render/blankLines.ts`: computes, for each two
     consecutive top-level blocks, the actual number of blank lines from the sourcepos gap
     and where needed inserts a pure spacer `<div>` with `height: Nem` BEFORE the block
     (additively, so that the theme's own paragraph/heading margin is left untouched instead of
     being overridden). `docModel.ts`'s `BlockPos` extended by `endLine`. Wired like
     zoom/cursor/overlay: `browser.preserve_blank_lines` (default `false`) in `DEFAULTS.lua`,
     `?blanklines=1` in `launcher.lua`'s URL construction (only when `true`, as with `zoom`), a
     new `lua/mdview/bindings/usrcmds/blanklines.lua` plus a route in `usrcmds/init.lua`, live
     update over the same `/control` channel (`{blankLines: bool}` — the wire key deliberately
     stays different from the config field name, as with `cursor_marker` → `cursor`). Verified
     end to end: locally built relay via `:MDView start` (with the new
     `dev.binary_path`/`dev.web_root`, see "General"), `:MDView blanklines on` → notification
     confirmed plus `/control` posted directly with `{"blankLines":true}` → `204`. Lua test
     suite (24/24) and ESLint on the new/changed client files green; `tsc --noEmit` only breaks
     on the generated `wasm-render` file missing in this worktree (never built, unrelated to
     this change) — no type errors otherwise.

---

## UX: browser modes and the rendering look

  1. ~~The preview opened in a separate window (not as a tab in the normal browser) and without
     the user's extensions/appearance~~ — new `browser.open_mode` (default `"default"`):
     - `"default"`: opens the URL in the user's default browser as a new tab (via
       `vim.ui.open`, falling back to `start`/`open`/`xdg-open`) — their extensions, their
       theme, their profile. Trade-off: mdview cannot close the tab programmatically, so
       `browser_autoclose`/`stop_on_browser_exit` are no-ops in this mode (the
       markdown-preview.nvim approach, see `markdown_preview/browser/tab.md`).
     - `"isolated"`: the previous behaviour (own profile, own process) — auto-close
       works reliably, but without the user's extensions/bookmarks.
     Cooperative closing in default mode (a WS `close` event → `window.close()`) is recorded as
     a medium task in [`ROADMAP.md`](ROADMAP.md).
  2. ~~Rendered markdown looked bad (the client HTML had practically no CSS)~~ — a built-in
     GitHub-like theme (`src/client/themes/github.css`, light/dark automatically via
     `prefers-color-scheme`, plus `data-theme` pinning). Theme selection through `browser.theme`
     (passed to the client as `?theme=`) plus lazily loaded `THEME_LOADERS` in `main.ts` →
     further themes are a CSS file plus a map entry. Verified end to end in a real browser
     (headings with a border, code blocks, tables, blockquotes, dark mode). The "external
     renderer website" idea is recorded as an opt-in task in [`ROADMAP.md`](ROADMAP.md) (with a
     privacy note: it contradicts the loopback-only model) — `browser.open_url` is already the
     escape hatch for an arbitrary URL.
  3. ~~GFM task lists (`- [ ]` / `- [x]`) were rendered without a checkbox~~ — ammonia stripped
     the `<input>` elements (not in the default allowlist). The sanitizer in
     `native/wasm-render/src/lib.rs` now specifically allows `<input>` with only
     `type`/`checked`/`disabled` (checkboxes cannot execute JS, there is no form context, and
     `formaction`/event handlers are still removed — with the test
     `strips_dangerous_input_attributes`).

---

## Performance: `:MDView start` vs. `:MDView standalone`

  1. ~~Does `standalone` relieve Neovim compared to the normal `start` path?~~ — yes, clearly and
     drastically measured. Controlled benchmark: 150 discrete edits to a markdown file,
     once through `:MDView start` (edits via `nvim_buf_set_lines` in the same instance that also
     holds the relay child process), once through `:MDView standalone` (the same 150 edits made
     externally via `Add-Content` directly on the file, while the nvim instance that started it
     merely sits alongside). What was measured is the CPU time of the nvim.exe process itself
     (`Get-Process .TotalProcessorTime` delta, Windows).
     - **`start`: 1875 ms CPU** for 150 edits (~2.9 s wall time) — nvim was actively busy on the
       CPU for most of that time.
     - **`standalone`: 0 ms CPU** — completely unchanged, even though the same 150 edits
       arrived at the observed file.
     - Cause found: `bindings/autocmds/live_push.lua` does **not** throttle — every
       `TextChanged`/`TextChangedI` (potentially every keystroke in insert mode) immediately
       spawns its own `curl` process via `vim.fn.jobstart` for the full buffer push. With
       `standalone` that path does not exist at all — the relay observes the file with
       its own (Go-side) watcher, completely decoupled from Neovim.
     - ~~Possible follow-up optimization: throttle `live_push` (similar to `scroll_sync_throttle_ms`)~~ —
       implemented. New `live_push_throttle_ms` (default 150, like `scroll_sync_throttle_ms`) in
       `lua/mdview/bindings/autocmds/live_push.lua`. Unlike the scroll-sync throttle (which simply
       discards a ping that comes too early — uncritical for a transient scroll position), a
       content push must not be discarded, or the preview would stay permanently out of date
       without anything else triggering a resync. Hence: a push inside the throttle window is not
       discarded but deferred onto a single trailing timer (at most `throttle_ms`
       delay, no rescheduling on each further keystroke) — the latest state is guaranteed
       to arrive. `BufWritePost`'s full push on save deliberately stays unthrottled
       (rarer, and it serves as a resync point). Verified with the same benchmark as above: 150
       edits under `:MDView start` fell from 1875 ms to **937.5 ms CPU** (−50%). Lua test suite
       (24/24) still green.

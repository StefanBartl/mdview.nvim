# Tests

mdview.nvim's Lua/Neovim tests live under two roots, mirroring the
distinction the CI `lua` job (`.github/workflows/ci.yml`) makes:

- `TESTS/lua/*_spec.lua` — plain [busted](https://lunarmodules.github.io/busted/)
  specs (`describe`/`it`, real `luassert`) for **pure Lua modules with no
  `vim` global** (`.busted` puts `lua/` and a `lib.nvim` checkout on the
  module path). Run with `busted TESTS/lua`.
- `TESTS/nvim/*_spec.lua` — specs for modules that need the real Neovim API.
  These run inside a headless Neovim instead of under busted (which has no
  `vim`), via a tiny bundled harness (`TESTS/nvim/harness.lua`) that provides
  just enough of busted's surface (`describe`/`it`, a small `assert`) to
  discover and run every `TESTS/nvim/*_spec.lua`, then exits non-zero (`:cq`)
  on any failure. The harness resolves `lib.nvim` itself (mdview.nvim hard-
  depends on it) via `$LIB_NVIM_PATH`, a sibling `../lib.nvim` checkout,
  `.deps/lib.nvim` (where CI clones it), or lazy.nvim's data dir — see
  `harness.lua`'s `add_lib_nvim()`.

Run locally the same way CI does:

```sh
busted TESTS/lua
nvim --headless -u NONE -i NONE --cmd "set rtp+=.,../lib.nvim" -c "luafile TESTS/nvim/harness.lua" -c "qa!"
```

(swap `../lib.nvim` for wherever your lib.nvim checkout actually is, or set
`$LIB_NVIM_PATH` — see above).

Neither suite calls `require("mdview").setup()`: that resolves the browser
and registers user commands, both of which are environment-sensitive (and
setup() is itself covered directly, see below) — specs require the modules
under test and read/patch config defaults instead, so they stay pure unit
tests.

## Non-Lua test assets in this directory

`TESTS/` also holds fixtures and tests **outside** the two suites above —
left alone by this round, listed here so they aren't mistaken for stray
files:

- `TESTS/client/*.test.ts` — the TypeScript/Vitest suite for the browser
  client (`src/client/`), run by the CI `node` job (`npm test`), not the Lua
  `lua` job. Different ecosystem, different test runner.
- `TESTS/CHECK.md` — a hand-run manual release checklist (things that need a
  real browser/eyes, e.g. the `browser.behavior` matrix, opt-in experimental
  features "feeling" right). Not automated by design.
- `testfile.md`, `linkfile.md`, `any_file/`, `resources/` — fixture documents
  and binary/script samples the manual checklist and the client tests point a
  real preview at (links, images, non-Markdown files for `any_file`). Not
  Lua test inputs.

## Coverage — round 25

Before this round: 19 spec files (`smoke_spec.lua`, `line_diff_spec.lua`,
`breadcrumbs_spec.lua`, `buffer_switch_resync_spec.lua`, `buffer_switch_spec.lua`,
`config_spec.lua`, `fence_spans_spec.lua`, `field_spec.lua`,
`line_diff_transport_spec.lua`, `log_scratch_spec.lua`, `path_for_url_spec.lua`,
`pin_spec.lua`, `previewable_spec.lua`, `reverse_scroll_spec.lua`,
`scroll_sync_routing_spec.lua`, `selection_sync_autocmd_spec.lua`,
`selection_sync_spec.lua`, `server_args_spec.lua`, `toggle_spec.lua` — 19
files) exercised roughly a quarter of the 78 files under `lua/mdview/`:
solid, deep coverage of the live-session core (`core/state`, `core/pin`,
`core/fence_spans`, `core/breadcrumbs`, the four live autocmds, `config`,
`config/browser`, `helper/previewable`, `helper/normalize`,
`adapter/server_args`, `adapter/inbound_poll`), but whole directories —
`adapter/browser/*`, `adapter/{control,detached,install,log,preview_tab,runner}.lua`,
17 of `bindings/usrcmds/*`'s 19 action files (only `log.lua` and `pin.lua` had
coverage), the entire `bindings/usrcmds/start/*` tree, `core/{events,session}.lua`,
`utils/{diff,diff_granular}.lua` — had none.

11 new spec files close most of that gap:

- `adapter_log_spec.lua` — `adapter/log.lua`: file-logging toggles/overrides,
  the hand-rolled Windows-aware `ensure_dir`/`path_dirname` pair (creates
  nested log-file directories, including the drive-letter branch — exercised
  for real wherever the suite actually runs on Windows), the ring buffer
  (multi-line splitting, ANSI stripping, the 2000-line cap), and `M.show()`'s
  scratch-buffer reuse.
- `launcher_url_spec.lua` — `start/server/launcher.lua`'s `resolve_browser_url`
  (every `?param=` the client reads: theme/highlighter/extlinks/cursor/zoom/
  selection/blanklines/webtransport+cert-hash/click_navigate/reverse_scroll/
  sync_checkboxes/sync_fields, plus the open_url/dev-port/key+token
  precedence) and `has_display`. Previously untested despite being fully
  public and side-effect-free.
- `start_args_spec.lua` — `start/init.lua`'s `parse_start_args` (`cwd=`/`port=`
  parsing, quote-stripping, order-independence), exposed as
  `M._parse_start_args` for exactly this (see "Internals exposed for
  testing" below).
- `usrcmds_preview_controls_spec.lua` — the eight live-control
  `:MDView <action>` commands that push a `/control` update when a session is
  running and just record the choice otherwise: `blanklines`, `cursor`,
  `overlay`, `reveal`, `selection`, `sync`, `zoom` (full clamp/rounding
  matrix), `theme` (incl. the "re-open the preview" branch, `mdview.open`
  stubbed). All previously untested.
- `usrcmds_session_actions_spec.lua` — `stop` (detach/close/reset sequencing,
  `browser_autoclose` precedence, `ws_client.send_close` stubbed so it can't
  shell out to a real curl POST), `toggle` (dispatch only, start/stop
  stubbed), `open`, `diagnose` (real file + real tab, temp path), `file-log`
  (the usrcmd wrapper around what `adapter_log_spec.lua` covers directly),
  `breadcrumbs`/`show_weblogs`/`preview-tab` (the usrcmd wrappers; the modules
  they delegate to are covered in `breadcrumbs_spec.lua` /
  `adapter_log_spec.lua` / `preview_tab_spec.lua`).
- `preview_tab_spec.lua` — `adapter/preview_tab.lua` (the in-Neovim-tab
  preview, fully independent of the browser/relay): open/close/toggle/sync
  against real tabs and buffers, refocus-instead-of-reopen, and — the
  buffer/window teardown family this campaign specifically watches for —
  what happens when the preview buffer is wiped out from under the module by
  something other than its own `M.close()` (`:bwipeout!`, and a real
  file/explorer taking over the preview's tab via `handle_displacement`).
  Previously completely untested.
- `browser_args_spec.lua` — `adapter/browser/build_args_for_browser.lua`
  (Chrome/Firefox/generic arg shapes, persistent profile dir) and
  `adapter/browser/resolve_command.lua`'s `explicit_cmd`/config precedence
  (against real temp executables, same pattern as `server_args_spec.lua`).
- `detached_spec.lua` — `adapter/detached.lua`'s `build_env` (env-list
  merging/override) and `resolve_target` (explicit arg vs. current-buffer
  fallback, both success and error paths).
- `install_status_spec.lua` — `adapter/install.lua`'s `M.status()` against a
  disposable, never-real `install.version` string (no network, no real
  cache touched).
- `session_events_spec.lua` — `core/session.lua` (store/get/init/shutdown,
  `compute_line_diff`) and `core/events.lua` (`push_buffer`,
  `store_snapshot_on_enter`). Both are dormant (superseded by
  `bindings/autocmds/live_push.lua`/`bufenter.lua` — see `core/events.lua`'s
  own module docstring) but still real, reachable logic that had zero
  coverage; see "Bugs found" below for what turned up here.
- `diff_granular_spec.lua` (`TESTS/lua/`) — pins the bug `utils/diff_granular.lua`
  already documents about itself in its own module comment.

Total: 19 → 30 spec files. 120 → 239 checks in the headless-nvim harness (all
green, stable across repeated runs); 8 → 13 checks in the busted suite
(`line_diff_spec.lua`'s 7 + `smoke_spec.lua`'s 1, plus `diff_granular_spec.lua`'s
new 5).

### Bugs found this round

All three are in **dormant** code (`utils/diff_granular.lua` and its only
caller, `core/events.lua` — both superseded by `utils/line_diff.lua` /
`bindings/autocmds/live_push.lua` on the live session path; see those
modules' own docstrings) and are pinned as `BUG:`-marked regression
assertions rather than fixed, since a real fix means porting `core/events.lua`
to `utils/line_diff` — a deliberate architecture change to unused code, not a
trivial edit:

1. **`utils/diff_granular.lua`'s Myers backtrace drops same-length
   replacements entirely.** A single changed line (the single most common
   edit) among unchanged lines around it produces **zero** edits — not a
   wrong edit, no edit at all. Pinned in `TESTS/lua/diff_granular_spec.lua`
   (four cases: mid-document replacement, a longer document, a pure trailing
   delete, and an insert into an empty document — all produce `#edits == 0`).
   The module's own docstring already calls itself "a buggy Myers attempt
   that dropped real changes"; this pins what that means concretely, since
   nothing had before.
2. **Consequently, `core/events.lua`'s `push_buffer(bufnr, false)` (the
   non-force live-diff path) silently sends nothing at all** for a
   same-length edit — pinned in `session_events_spec.lua`.
3. **When `diff_granular` *does* emit an edit** (an append/insert, a case its
   backtrace doesn't drop), `push_buffer` extracts the wrong chunk to send:
   it slices `new_lines` at `[d.start+1, d.start+d.count]`, but `diff_granular`
   always sets `count = 1` for an insert regardless of how many lines
   `d.lines` actually holds — so the sent chunk is whatever one line already
   sat at that position, not the inserted line(s). Pinned in the same file
   (`"BUG: a pure append is not dropped, but sends the WRONG line"`).

### Deliberately omitted, with reasons

- `@types/*.lua`, `types/*.lua` — pure `---@meta` annotations, no runtime
  code.
- `plugin/mdview.lua` (if present) / any bare load-guard one-liner — no
  branching logic.
- `adapter/runner.lua` — `M.start_server`/`M.stop_server` spawn a real
  `uv.spawn()` child process and wire real libuv pipes; `resolve_spawn_cwd`
  (the one pure helper) is trivial (`expand_path` + precedence) and not worth
  a dedicated suite on its own. No CI sibling relay binary exists to spawn
  against.
- `adapter/install.lua`'s `M.ensure_binary`/`M.ensure_client_bundle` (and the
  `curl_download`/`ensure_asset`/checksum helpers under them) — real network
  downloads from GitHub Releases plus a real `tar`/`chmod` subprocess. Only
  the network-free, filesystem-only `M.status()` is covered (see above).
- `adapter/browser/probe_platform_paths.lua` — mostly a declarative list of
  hardcoded candidate paths per platform; not worth asserting the literal
  path list itself (which platform's branch even runs depends on the OS
  actually running the suite), and exercised as a fallback inside
  `resolve_command`'s autodetect tests. Its one real branch (the Windows
  env-var lookup) has its own regression test — see
  `probe_platform_paths_spec.lua` below.
- `adapter/browser/resolve_command.lua`'s autodetection/friendly-name/
  platform-probe branches beyond the `explicit_cmd`/config-precedence cases
  covered — depend on what happens to be installed and where on whatever
  machine runs the suite, not something a fixture can pin portably.
- `adapter/browser/init.lua`'s `M.open`/`M.close` — real `jobstart()` of an
  OS browser opener or an isolated browser process (`rundll32`/`open`/
  `xdg-open`, or a real Chrome/Firefox/generic launch). No stable mock
  surface without replacing the whole process layer.
- `bindings/usrcmds/standalone.lua` — spawns a real detached relay process
  and probes it via `vim.system()`; end-to-end only against a real binary.
- `bindings/usrcmds/start/init.lua`'s `M.run` beyond `parse_start_args` (see
  above), and `start/server/{launcher.lua's M.start, try_push.lua, waiter.lua}`
  — each ultimately spawns/waits on a real relay process
  (`runner.start_server`, `ws_client.wait_ready`'s real health polling loop).
  `launcher.lua`'s pure `resolve_browser_url`/`has_display` ARE covered (see
  above).
- `bindings/autocmds/{bufenter,bufwrite,breadcrumbs,vim_leave,on_text_change,
  preview_tab_sync}.lua` and `bindings/autocmds/init.lua` — thin
  attach/detach wiring around already-directly-tested logic
  (`core/session.store`, `core/events.push_buffer`, `core/breadcrumbs.record`,
  `ws_client.send_close`+`runner.stop_server`, `adapter/preview_tab`'s
  own sync/displacement — all covered where the real logic lives). Wiring
  four/five more copies of "does `autocmd.create` get called with the right
  event/pattern" would pad the suite without pinning anything new; the
  contracts they call into are pinned directly instead.
- `helper/{gen_token,is_windows,safe_buf_get_option}.lua` — one-line
  re-exports of `lib.nvim`/`vim.fn.sha256`+`vim.uv.hrtime` helpers, or (for
  `gen_token`) a thin wrapper with no branch of its own to assert against
  beyond "returns a string" (its actual entropy/uniqueness is `lib.nvim`'s or
  Neovim's concern, not this plugin's).
- `test/apply.lua`, `test/diff_harness.lua`, `test/runner.lua` — developer
  tooling for the (dormant) line-diff transport and for manually driving a
  real relay process from a REPL, not code any `:MDView` command path
  reaches. `diff_harness.lua` in particular is a standalone benchmark script
  (prints timing/ratio numbers), not a test suite itself.
- `diagnostics.lua`'s `M.collect` in full — `diagnose.lua`'s usrcmd wrapper
  test exercises `diagnostics.run()` end-to-end (including `M.collect`)
  against a real temp path with no session running, which is the one branch
  free of real network/process calls (a running session's `/health` GET is
  skipped by construction — see `usrcmds_session_actions_spec.lua`).
  `health.lua` was similarly excluded here as "declarative"; the 2026-09-18
  re-audit below found that reasoning didn't hold (real branches, and a real
  bug) and gave it its own spec instead — see that section. Still not
  covered: the exact ok()/warn()/error() *message text* `M.check()` reports
  (vim.health writes into the global report machinery, not a return value a
  spec can capture) and the real-curl-subprocess branch of its own `/health`
  probe (same real-network reasoning as `diagnostics.lua`'s, stubbed instead
  where it's reached at all).
- `config/usrcmd_start.lua` — a two-line re-export of the same shared
  `config.defaults.start` table `mdview.config` itself exposes (see
  `config/DEFAULTS.lua`); no logic of its own, `mdview.config`'s own coverage
  already exercises the table it points at.

## Internals exposed for testing

This round added one `_`-prefixed exposure of an otherwise-private pure
function, matching the convention already used elsewhere in this plugin
(`adapter/inbound_poll.lua`'s `M._handle_nav`/`_handle_scroll`/`_handle_toggle`/
`_handle_field`):

- `bindings/usrcmds/start/init.lua` — `M._parse_start_args` (the
  `cwd=`/`port=`/file token parser). Otherwise only reachable through the
  full `M.run()`, which spawns a real server process.

Purely additive: an existing local function gained one extra line
(`M._parse_start_args = parse_start_args`) exporting the same, unmodified
function under a new name. No behavior changed.

The 2026-09-18 re-audit (below) added a second one, same convention:

- `bindings/usrcmds/init.lua` — `M._log_level_routes` (the `log <level>`
  route-list generator). Otherwise only reachable through the full
  `M.attach()`, which registers a real `:MDView` user command as a side
  effect.

## Re-audit — 2026-09-18

A re-audit pass, not a rewrite: every skip reason above was re-checked
against the *current* source (only `start/server/launcher.lua`'s
`has_display()` had changed since round 25 — a genuine nil-vs-false bug it
already documents in its own comment, fixed and covered by
`launcher_url_spec.lua` at the time; nothing else under `lua/mdview/` had
changed). The specific bug patterns this campaign keeps finding elsewhere
(a health-check that warns about a missing dependency and then crashes into
it anyway; a non-idempotent augroup; byte/column confusion in text-position
logic; Windows path/colon bugs) were checked for directly rather than
assumed absent:

- **Augroup idempotency** (`bindings/autocmds/init.lua`): already correct
  and already documents its own past bug fix in a comment —
  `require("lib.nvim.bindings.autocmd").group("MdviewAutocmds", true)` uses
  `lib.nvim`'s cache-verified, `clear=true` group lookup, not a raw
  `nvim_create_augroup`/`get_augroup` that would double-register on a second
  `setup()`. No action needed.
- **Byte/column/char-index confusion** (`core/fence_spans.lua`,
  `bindings/autocmds/{selection_sync,scroll_sync}.lua`, `adapter/ws_client.lua`):
  every position value is consistently a documented 1-based or 0-based byte
  column (matching comrak's own `data-sp` convention), with comments at each
  site saying which. No confusion found; these are also the modules round 25
  already covered most deeply.
- **Windows path/colon bugs**: mdview.nvim's own Lua doesn't parse
  link/image paths itself (that's the client's `src/client` TypeScript side,
  covered by `TESTS/client/*.test.ts`, out of this audit's scope) or do any
  `string:find(":", ...)`-style parsing anywhere in `lua/mdview/`.
  `helper/normalize.lua`'s `path_for_url` already documents and works around
  the one real instance of this class of bug (a Windows drive letter's `:`
  breaking `rundll32`'s URL handling) from a past round.
- **lib.nvim sibling availability**: confirmed a real `lib.nvim` checkout
  exists at `../lib.nvim` (this repo's own CI clones it to `.deps/lib.nvim`
  for the same reason) — already correctly assumed present, not something
  this plugin got wrong. mdview.nvim also has no telescope/fzf-lua/snacks
  dependency anywhere to get wrong in the first place.

### Gap found and closed: `health.lua`'s crash-on-degraded-dependency bug

Exactly bug pattern (a) from this campaign's running list. `M.check()`
gracefully reports "lib.nvim not found" as a health *error* (not a crash) when
`lib.nvim.cross.platform.is_windows` fails to resolve — but its last line was
an **unguarded** `require("lib.nvim.bindings.usercmd.composer").checkhealth(...)`,
one `require` away from the exact same risk the line right above it
(`pcall(require, "lib.nvim.deps.health")`) already guards against. Any
lib.nvim old/partial enough to be missing that specific submodule crashed
`:checkhealth` outright, discarding every ok/warn/error already reported in
the same call — including the graceful one this function goes out of its way
to produce.

Fixed directly (trivial, zero behavior change on the normal path: same
`pcall(require, ...)` idiom already used one block above, in the same file):

```lua
local ok_composer, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
if ok_composer then
  composer.checkhealth("MDView")
end
```

Pinned in the new `TESTS/nvim/health_spec.lua` (simulates the missing
submodule via `package.preload`, confirmed to fail without the fix and pass
with it) alongside two non-bug smoke cases (`M.check()` under normal
conditions, and with a faked running session so the "attached/session token"
branch also runs — `vim.fn.system` stubbed directly, no real curl subprocess).

### Gaps found and closed: two unmentioned, genuinely uncovered files

Not stale skip reasons — these two were simply never mentioned by round 25's
"deliberately omitted" list at all, and had zero coverage:

- `helper/copy_lines.lua` — a shallow array copy (used on the live path by
  `bindings/autocmds/bufenter.lua`, not only by the dormant `core/events.lua`)
  with a real branch: `lib.nvim`'s `clone` when resolvable, a local loop
  fallback otherwise. Pure Lua, no `vim` global — new `TESTS/lua/copy_lines_spec.lua`
  covers both branches (the fallback forced via `package.preload`, since
  `has_lib_clone` is resolved once at module load), asserting each returns a
  real independent copy, not an aliased reference.
- `bindings/usrcmds/init.lua` — `M.attach()` (the `:MDView` route-tree
  registration) was never exercised at all: the harness deliberately never
  calls `require("mdview").setup()` (see harness.lua's own comment), the only
  normal path to it. The giant route table itself stays undertested by
  design (every route's target is already covered directly in its own spec —
  same reasoning as `bindings/autocmds/init.lua`'s wiring exclusion above),
  but `log_level_routes()` — generating one route per `log.LEVELS` entry and
  sorting them — is real, previously-untested logic, and `M.attach()`
  registering the command tree without erroring at all was itself unverified.
  New `TESTS/nvim/usrcmds_init_spec.lua` covers both, via the newly-exposed
  `M._log_level_routes` (see "Internals exposed for testing" above).

### Totals

Before this re-audit: 30 spec files, 239 headless-nvim checks, 13 busted
checks (all green, per round 25). After: **33 spec files** (+3:
`health_spec.lua`, `usrcmds_init_spec.lua` under `TESTS/nvim/` (29 total);
`copy_lines_spec.lua` under `TESTS/lua/` (4 total)), **247 headless-nvim
checks** (+8), **19 busted checks** (+6). All green, stable across repeated
runs (`nvim`'s harness and `busted` each run twice locally with identical
pass counts both times).

No new `BUG:`-pinned regressions were added this round beyond the one fixed
directly above (`health.lua`'s fix was trivial and unambiguous enough to fix
in place rather than pin, per this round's own instructions — unlike the
three dormant-code bugs round 25 pinned instead, this one is on a path
(`:checkhealth`) users actually run, and the fix has no behavior change on
the working path).

## Fix — 2026-09-20: `probe_platform_paths.lua` browser-detection bugs

Filename-typo fix (`probe_plattform_paths.lua` -> `probe_platform_paths.lua`)
prompted a closer look at the file itself, which turned up two real bugs on
the autodetect fallback path:

1. **Windows candidates built via a `{ os.getenv(...), ... }` table literal,
   then walked with `ipairs`.** `ipairs` stops at the first `nil` hole, so
   whenever `PROGRAMFILES(X86)` is unset (which it commonly is under Git
   Bash/MSYS2 — Windows env var names containing parentheses often don't
   pass through), every base *after* it (`LOCALAPPDATA`, where per-user
   Chrome installs live) was silently skipped, even though it was set. Fixed
   by building the candidate list with `table.insert` (skipping unset vars
   without leaving holes) instead of a literal with possible `nil` slots.
2. **The Linux probe list and the cross-platform `default_candidates`/
   `build_args_for_browser` name matching all used `msedge`**, which is the
   Windows binary name only; Microsoft Edge on Linux installs as
   `microsoft-edge`/`microsoft-edge-stable`. Edge was effectively
   undetectable on Linux despite the code's evident intent to support it.
   Fixed in all three places (`probe_platform_paths.lua`'s Linux branch,
   `resolve_command.lua`'s `default_candidates`, and
   `build_args_for_browser.lua`'s name match).

Pinned in new `TESTS/nvim/probe_platform_paths_spec.lua`: a Windows-only case
(stubs `os.getenv` to simulate `PROGRAMFILES(X86)` being unset, asserts a
`LOCALAPPDATA`-based candidate still appears) and a Linux-only case (asserts
`microsoft-edge` appears and the old `msedge` path does not). Both follow
this suite's existing convention of testing against whichever OS actually
runs it rather than mocking `vim.fn.has` (see `server_args_spec.lua`).

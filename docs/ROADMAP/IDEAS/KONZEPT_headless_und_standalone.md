# Concept: preview without a server, a background instance and a standalone binary

> **Status: implemented — with one correction after a practical test.** User docs:
> [`docs/standalone.md`](../../standalone.md). What was built:
> `native/server/internal/source` (`--watch`/`--open`), `:MDView standalone`,
> `standalone.binary_path`, `scripts/minimal_init.lua` and
> `scripts/mdview-bg.{sh,ps1}`.
>
> **`:MDView detach` (section 4, background nvim) was removed again after the
> test.** The practical test showed two problems the concept had underestimated:
> (a) the detached headless nvim opened the browser sometimes immediately,
> sometimes only after 10–15 min, sometimes never — the input-driven headless main
> loop processes pending libuv events unreliably when it idles without stdin;
> (b) more fundamentally: the detached instance holds a **static buffer** (no
> autoread, no fs watch), so a live push never reaches it — the claimed benefit
> "full editor features in the background" does not in fact exist, because nobody
> edits in a headless instance. `detach` was thereby dominated by `standalone` in
> every practical respect (a static snapshot + unreliable vs. following the file
> live + robust). The terminal wrapper now points at `standalone`.
>
> Left open: section 1 option A (static HTML export) and section 3.4/stage B (an
> own single binary with `go:embed`).
>
> This document remains as the basis for the decision — including the
> overestimated section 4, so that the lesson is documented. The text below is the
> original state of the concept.

> It answers three related questions:
> (1) Can the main feature be offered without starting a server? (2) Can mdview be
> started as a background process from a terminal
> (`nvim --headless ... file.md`), optionally with a browser tab or as a separate,
> minimal nvim instance? (3) Is an experimental, nvim-independent standalone mdview
> realistic, cross-platform, in Lua/Go/WASM? All three answers build on the
> existing architecture (see `docs/architecture.md`) — none of them requires a
> rewrite.

---

## 0. Starting point (current state)

For context, what already exists and what would be new:

| Building block | Status today |
|---|---|
| Go relay (`native/server`) | A pure byte relay: it takes markdown text via `POST /update` from nvim and broadcasts it over WebSocket. It renders nothing itself. It knows only the one content source "nvim sends a POST". |
| Rendering (`native/wasm-render`) | Rust/comrak+ammonia → WASM, runs **in the browser**, and is completely decoupled from the content source (it receives raw markdown text over WS and does not care where it came from). |
| `:MDView preview-tab` | Renders **without** relay/browser/WASM — treesitter highlighting of a mirror buffer in a new nvim tab. The only serverless variant that exists today. |
| Process spawning | `lua/mdview/adapter/runner.lua:M.start_server` uses `vim.loop.spawn` (libuv), not `jobstart`/`vim.system`. No `detached` flag in use. |
| Cross-build | `native/server/.goreleaser.yml` already builds the Go relay for linux/darwin/windows × amd64/arm64. Pure build infrastructure, not a standalone product. |

The most important finding: **the relay knows nothing about files.** It only knows
"here is text for key X, distribute it". That is the lever for all three points
below — the content source is exchangeable without touching the client or the WASM
renderer.

---

## 1. The main feature without starting a server

**Question:** is there a way to offer the main feature without starting a server?

**Short answer:** partly yes, and it already exists (`:MDView preview-tab`), but
with reduced functionality. A full serverless variant with identical rendering is
possible, but only with compromises — WASM necessarily needs a host with a JS
engine (browser or Node), and websocket live sync necessarily needs a process that
listens.

### 1.1 What "without a server" actually means

Three levels that often get lumped together:

1. **No dedicated server process** (no `mdview-server.exe` as a child process) —
   but possibly still a browser tab.
2. **No browser** — rendering stays in the terminal / in nvim.
3. **No live-update channel** — static rendering that has to be triggered anew on
   every change.

`preview-tab` fulfils all three: no server process, no browser, but also no
WASM/CSS theming — only treesitter markdown highlighting in a mirror buffer. That
is enough for a quick proofread; not for the actual "main feature" (cleanly
rendered HTML with a theme, sanitising, scroll sync).

### 1.2 Option A — a static one-off export (no server, but a browser)

The existing Rust/comrak renderer currently runs only as WASM in the browser.
comrak itself, though, is an ordinary Rust library — a second, small Rust or Go CLI
target (`render-once`) could render markdown directly into a self-contained HTML
file (client CSS/JS bundled inline, no `<script>` waiting on a WebSocket) and open
it via `file://` in the default browser. No server process, no open port, no token
— but also no live reload: every change needs another export call.

- Effort: small to medium (a new cargo or Go binary target that reuses the existing
  comrak/ammonia path, plus an "inline instead of WS" render path in the TS client
  or a separate, minimal static template).
- Fits well as `:MDView export [path]` — useful for sharing/doc export, not as a
  replacement for the live preview.

### 1.3 Option B — upgrade `preview-tab` instead of building anew

More obvious: bring `preview-tab` step by step closer to the browser preview,
without the server requirement:

- Currently only treesitter highlighting. In perspective the same comrak renderer
  (natively compiled, not as WASM) could be used to precompute additional metadata
  (e.g. resolved links, table column widths) and display it in the mirror buffer
  via `extmarks`/virtual text — no real HTML/CSS, but closer to the final result
  than pure syntax highlighting.
- Terminal graphics protocols (Kitty graphics protocol, Sixel) would be a bigger
  leap (embedded images/diagrams in the terminal), but that is a separate,
  considerably more expensive concept and only pays off if "without a browser" (not
  just "without a server") is a hard goal.

**Recommendation:** for the question as asked, `preview-tab` is already the answer
"the main feature without a server"; if more rendering fidelity is wanted, option A
(static export) is the more pragmatic next step, since it reuses the existing
comrak path directly.

---

## 2. A background-process API from the terminal

**Question:** `nvim +MDView --background "C:\TEST.md"` — start mdview as a
standalone background process, optionally with a browser tab or as a separate,
minimal nvim instance (only nvim + mdview installed).

Important up front: `nvim +MDView --background file.md` is not valid nvim CLI
syntax (`+cmd` takes no following flags). The real basis is
`nvim --headless -c "<cmd>" file.md`, combined with a minimal config and a detach
mechanism. That can be wrapped cleanly in a wrapper command, though.

### 2.1 Why this almost works today already

`:MDView start` already starts the relay as a child process and can run headless —
the server needs no GUI, and `browser.require_display` already suppresses the
`open` step in a controlled way when there is no display (see
`docs/checkpoints/01_checkpoint.md`). What is missing is not new functionality in
the relay, but:

1. A **start command from outside** (from a terminal, not from a running nvim
   instance).
2. A **minimal, isolated config** that loads only `mdview.nvim` (+ its `lib.nvim`
   dependency) instead of the full user config.
3. A **detach**, so that the process outlives the terminal that started it.

### 2.2 Proposed invocation

```sh
# Minimal form: a dedicated, isolated process, headless, with a fixed minimal config
nvim --headless -u <mdview-repo>/scripts/minimal_init.lua \
     -c "MDView start" "C:\TEST.md"

# The equivalent as a slim wrapper (a new, optional CLI script in the repo):
mdview-bg "C:\TEST.md"                 # browser tab (default open_mode)
mdview-bg --no-browser "C:\TEST.md"    # relay only, no tab (e.g. for external clients)
```

`scripts/minimal_init.lua` would be a ~10-line file: extend `rtp` only by
`mdview.nvim` and `lib.nvim`, `require("mdview").setup({})`, done — exactly the
"own isolated instance where only nvim and mdview are installed" from the request.
At its core that is identical to the existing test-harness pattern
(`b1151c1 test(harness): resolve lib.nvim instead of requiring it on the
invocation's rtp` — a working minimal-RTP resolution already exists there and can
be reused).

`mdview-bg` itself would be a thin shell/PowerShell script (analogous to
`dev:server` in `package.json`) that:

- resolves the target file to an absolute path,
- starts `nvim --headless -u minimal_init.lua -c "MDView start" <file>` **detached**
  (Unix: `setsid ... &`; Windows: `Start-Process -WindowStyle Hidden`),
- optionally passes `--no-browser` through as `browser.browser_autostart=false` into
  the minimal_init.

### 2.3 Two operating modes for the background process

| Mode | Behaviour | Use case |
|---|---|---|
| **With a browser tab** (default) | The headless nvim starts the relay + opens the browser tab as usual, then keeps running in the background and pushes changes (the `live_push` autocmd works identically headless). | Quick "call it once and forget it" — the preview stays open, the terminal is free again. |
| **Without a browser** (`browser.browser_autostart=false`) | Only the relay + WS endpoint run; no tab is opened. | Remote access (open the preview from another machine on the same network), or a precursor to the standalone client from section 3. |

### 2.4 What would technically be new

- **A detach flag on the spawn**: `runner.lua`'s `vim.loop.spawn` would need
  `detached = true` *if* the detach is supposed to happen from a running nvim
  instance (section 4). For the external terminal call (`mdview-bg`) the operating
  system/shell handles the detach and nvim itself needs nothing new.
- **`minimal_init.lua`**: a new, small file in the repo (no plugin code, only
  bootstrap).
- **Wrapper script(s)**: `scripts/mdview-bg.sh` + `scripts/mdview-bg.ps1`, thin,
  duplicating no logic — they only call `nvim` with the right flags.
- **No intervention in the relay/client needed** — the entire change is process
  orchestration, not a protocol change.

---

## 3. An experimental standalone mdview (without nvim)

**Question:** the feasibility of a standalone, cross-platform mdview — Lua, Go,
WASM as the candidates.

### 3.1 Core idea: give the relay a second content source

The relay today knows exactly one content source: `POST /update` from nvim. For
standalone operation it needs a second, alternative source — **filesystem watching**
— that internally feeds the same `registry.Broadcast(key, content)` path that
`handleUpdate` in `native/server/main.go:171` fills over HTTP today. The client,
the WASM renderer, the WebSocket framing, the sanitising — all stay unchanged,
because the registry does not know (and does not need to know) whether the text
came from nvim or from a filesystem watcher.

```
Today:      nvim (buffer events) --HTTP POST /update--> registry --WS--> browser/WASM
Standalone: fsnotify (file events) --Go function call--> registry --WS--> browser/WASM
```

### 3.2 Language choice: Go, Lua, WASM compared

| Candidate | Suitability as the CLI host for a standalone mdview |
|---|---|
| **Go** | Already the implementation language of the relay. With `internal/relay` it already has 90 % of the necessary logic (registry, WS, auth, static file serving). `fsnotify` is an established, cross-platform library (linux/darwin/windows). `go:embed` allows the built client (`dist/client/`) to be embedded **into the binary** — real single-binary deployment without external assets. A cross-compile pipeline (`goreleaser`) already exists for all three target platforms. **A clear favourite.** |
| **Lua** | There is no production-ready, cross-platform Lua standalone HTTP server + file watcher stack without an external runtime (LuaJIT+luv, OpenResty, or similar) — that would in effect be a new dependency chain parallel to Go, reusing nothing. Inside nvim, Lua is already the right choice (that is the plugin code itself); as an *nvim-independent* process, Lua brings no advantage over Go, only extra operational overhead. **Not recommended as the host.** |
| **WASM** | WASM is not a CLI host — it needs a host runtime itself (browser, Node, or a WASI runtime such as Wasmtime as an additional dependency). The existing WASM renderer stays in play unchanged, though: it still runs *in the browser* that the standalone Go process serves — only the content supply changes, not the rendering. A WASI variant of the relay itself would only matter for sandbox/plugin-host scenarios (e.g. embedding in another editor), which are not asked for here. **Stays as it is today: a rendering layer, not a process host.** |

### 3.3 Proposed architecture

A new build target `mdview-standalone` (its own `main` in
`native/server/cmd/standalone/`, or a `--watch` flag directly on the existing
`mdview-server`, see 3.4) that:

1. **Takes a file argument instead of a token/nvim coupling**:
   `mdview <file.md> [--port 43219] [--theme dark] [--no-open]`.
2. **Runs an fsnotify watcher** on the file (and optionally on its directory for
   relative links/images) that, on changes, reads the file content and calls
   `registry.Broadcast(key, content)` directly — no HTTP hop, since everything runs
   in the same process.
3. **Uses `go:embed` for `dist/client/`**: the client bundle + WASM renderer are
   embedded into the binary at build time, and `--web-root` becomes unnecessary for
   the standalone case. Result: one single executable per platform, no `dist/`
   directory needed.
4. **Token**: generated locally as today (a `gen_token` equivalent in Go), since it
   remains loopback-only — no security deviation from the existing model.
5. **Opening the browser**: the same cross-platform `xdg-open`/`open`/`start` logic
   that currently sits in Lua (`lua/mdview/adapter/browser/`) would need a small Go
   equivalent (packaged libraries such as `pkg/browser` already exist for it).

### 3.4 Two build-out stages (effort vs. benefit)

| Stage | Description | Effort |
|---|---|---|
| **A — a flag on the existing relay** | `mdview-server --watch <file>` as an additional mode next to the `--token`-based nvim operation. No new binary, minimally invasive. | Small: a new `internal/source` package (fsnotify watcher → `registry.Broadcast`), one new flag, no existing code paths touched. |
| **B — an own `mdview` single binary** | A separate build target with `go:embed`, its own browser opener, its own CLI interface (`mdview file.md`, no nvim vocabulary such as `--token`). Clearly marketable/documentable as a standalone product. | Medium: a new `cmd/` directory, extending the `goreleaser` config by a second artefact, its own docs (`docs/standalone.md`). |

**Recommendation:** start with stage A as an experimental flag (quickly verifiable,
nothing existing endangered), and move to stage B once it has proven itself.

### 3.5 What explicitly stays the same

- The relay protocol (WS framing, the `\x01`–`\x05` prefixes), the client, the WASM
  renderer: **unchanged.**
- The security model (loopback-only, token, origin check): **unchanged**, only the
  token generation moves from Lua to Go for the standalone case.
- No impact on the nvim plugin path — standalone is an additional build target, not
  a replacement.

---

## 4. Both start modes from a running nvim instance

**Question:** both possibilities (background nvim, standalone binary) should also be
triggerable from a running nvim instance via a usercmd — "start the same thing in a
new instance".

The obvious form is two new routes in the existing `:MDView` routing
(`lua/mdview/bindings/usrcmds/init.lua:54`), analogous to `start`/`stop`:

```lua
{ path = { "detach" },
  desc = "Start a detached, minimal-config nvim --headless instance previewing this file, then keep this instance untouched",
  run  = function(ctx) detach.run(ctx.rest) end },

{ path = { "standalone" },
  desc = "Start the standalone mdview binary (no nvim) for this file, once it exists",
  run  = function(ctx) standalone.run(ctx.rest) end },
```

- **`:MDView detach`**: builds on `runner.lua`'s spawn pattern, but with
  `detached = true` in the `vim.loop.spawn` options table (libuv supports it
  natively) and the command from section 2.2 (`nvim --headless -u minimal_init.lua
  -c "MDView start" <current file>`). The calling instance keeps running unchanged —
  a completely second, independent process is created that keeps running even after
  `:qa` in the first instance.
- **`:MDView standalone`**: as soon as 3.4/stage A or B exists, a simple
  `vim.loop.spawn` on the `mdview-standalone` binary path (a new config field
  `standalone.binary_path`, auto-download analogous to the existing `install.lua`
  mechanism for `mdview-server.exe`) — no nvim in the process chain any more once
  the call has been issued.
- A shared prerequisite: the spawn helper in `adapter/runner.lua` would need a
  `detached` options field (not set today, since the relay child process is
  deliberately bound to the current nvim instance and is terminated with it by the
  `VimLeavePre` autocmd — for `detach`/`standalone` that is exactly what is *not*
  wanted, hence a dedicated code path instead of reusing `start_server`).

---

## 5. Summary / prioritisation

| # | Undertaking | Effort | Risk to what exists |
|---|---|---|---|
| 1 | `preview-tab` stays the serverless answer; possibly add option A (static export) | small–medium | none (additive) |
| 2 | An `mdview-bg` wrapper + `minimal_init.lua` for an external terminal start | small | none (pure process orchestration, no protocol/code-path intervention) |
| 3 | A `--watch` flag on the relay (stage A) as the foundation for standalone | small–medium | none, if implemented as a separate code path (`internal/source`) |
| 4 | `:MDView detach` / `:MDView standalone` as new routes | small (a detach flag in the spawn helper) | low, as long as it is kept as its own code path next to `start_server` |

The order 2 → 4(detach) → 3 → 4(standalone) yields an independently usable,
verifiable intermediate result at every step, without any step revising the
architectural decisions of the previous ones.

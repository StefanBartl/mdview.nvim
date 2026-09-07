# Contributing to mdview.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/mdview.nvim/issues); pull
requests very welcome.

This repository is four languages in one — Lua in the editor, Go in the relay,
Rust compiled to WASM for the renderer, TypeScript in the browser client. The
build for each is [`development.md`](development.md); this page is about which
of them a change belongs in, and the rules that hold across all four.

## Getting the repository into a session

Editing Lua only? Build nothing. Point your plugin manager at the checkout and
let the downloaded release binary and bundle do the rest:

```lua
{ dir = "/path/to/mdview.nvim", dependencies = { "StefanBartl/lib.nvim" }, opts = {} }
```

Touching the relay, the renderer or the client means building that component —
[`development.md`](development.md) has the toolchain table and the three build
variants. A build sitting inside the checkout (`native/server/mdview-server[.exe]`,
`dist/client`) is auto-detected and used ahead of the release, so the `dev.*`
overrides are only for a build kept somewhere else.

## Ground rules

- **Nothing renders on the server.** The relay moves bytes; it never turns
  Markdown into HTML. Rendering and sanitization both happen client-side, in
  the Rust/WASM module, so untrusted input passes an allowlist before it can
  become DOM content. A convenience that renders a fragment in Go or in Lua
  gives that guarantee away, whatever it saves.
- **The relay stays loopback-only.** It binds `127.0.0.1`/`localhost` and never
  a routable interface. Every write endpoint requires the per-session token,
  compared in constant time; WebSocket upgrades require an exact `Origin`
  match. An empty expected token must never validate — a misconfigured session
  fails closed. See [`FEATURES/SECURITY.md`](FEATURES/SECURITY.md) before
  touching anything in `native/server/internal/relay/`.
- **mdview mirrors, it does not edit.** The preview reflects buffer text; it
  does not transform it. Editing features belong in
  [markdown.nvim](https://github.com/StefanBartl/markdown.nvim), and they reach
  the preview for free because they change the text. The two deliberate
  exceptions are the checkbox and form-field write-backs, and both are
  opt-in config keys.
- **Companions are never loaded.** markdown.nvim and color_my_ascii.nvim are
  detected, never required. `:checkhealth mdview` notes their presence; nothing
  else may depend on it.
- **Two previews stay independent.** `:MDView start` (relay, WebSocket, WASM,
  browser) and `:MDView preview-tab` (a read-only mirror buffer, no relay, no
  browser) run on separate lifecycles. A live control must not reach into the
  plain tab, and vice versa.
- **A control command does two things and says which.** `cursor`, `zoom`,
  `overlay`, `reveal`, `sync`, `theme` and `blanklines` write the shared config
  *and* push a live update when a session is up. A new control follows the same
  shape, so running it without a session is never wasted work.
- **Diagnosability is a feature.** Anything that can fail goes through
  `lua/mdview/log.lua` and shows up in `:MDView diagnose`. A failure mode with
  no trace in the log ring or the report is not finished.
- Lua: 2-space indentation, `stylua.toml`. TypeScript: prettier and eslint, as
  configured. Go and Rust: the standard formatters.
- Descriptive commit messages.

## Which component

| Change | Goes in |
| --- | --- |
| A `:MDView` subcommand, a keymap, an autocommand | `lua/mdview/bindings/` over `lua/mdview/core/` |
| Session lifecycle, pinning, breadcrumbs, shared state | `lua/mdview/core/` |
| Talking to the relay, the browser, or the filesystem | `lua/mdview/adapter/` |
| Transport, endpoints, auth, the file watcher | `native/server/` (Go) |
| Markdown → sanitized HTML | `native/wasm-render/` (Rust) |
| What the browser tab shows and how it behaves | `src/client/` (TypeScript) |
| A `setup()` option | `lua/mdview/config/`, plus [`configuration.md`](configuration.md) |

The rule of thumb: if it can be done in Lua without weakening the security
posture, do it in Lua — the other three components are harder to change, harder
to test, and shipped as binaries.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/mdview/core/` | Session, state, events, pinning, breadcrumbs, fence spans |
| `lua/mdview/adapter/` | The relay runner, the WebSocket client, install, browser, detached mode, the in-editor preview tab, inbound polling, logs |
| `lua/mdview/bindings/` | The `:MDView` command tree, autocommands and keymaps |
| `lua/mdview/config/`, `types/`, `utils/`, `helper/` | Defaults and validation, LuaLS types, helpers, token generation |
| `lua/mdview/log.lua`, `diagnostics.lua`, `health.lua` | The log ring, `:MDView diagnose`, `:checkhealth mdview` |
| `native/server/` | The Go relay: transport, endpoints, auth, the standalone file watcher |
| `native/wasm-render/` | The Rust renderer: comrak plus ammonia, compiled to WASM |
| `src/client/` | The browser client |
| `scripts/` | The Go build script, the background launchers, `minimal_init.lua` |
| `doc/`, `docs/` | The vimdoc, and everything the README links to |
| `TESTS/` | The Lua and client suites plus their fixtures |

[`architecture.md`](architecture.md) says how the four talk to each other.

## Adding a control command

1. Put the state in `lua/mdview/core/` and the outbound message in
   `lua/mdview/adapter/`.
2. Route the subcommand in `lua/mdview/bindings/`, with completion over every
   closed argument set.
3. Write the config *and* push the live update, and report which of the two
   happened — see the ground rules.
4. If the browser has to do something new, the message shape is a change in
   both `src/client/` and the relay's endpoint list; keep the name identical
   across all three.
5. Add a spec, and document it in [`commands.md`](commands.md),
   [`BINDINGS.md`](BINDINGS.md) and the matching page under
   [`FEATURES/`](FEATURES/README.md).

## Tests

Four suites, one per language:

```bash
npm test              # client (vitest)
npm run test:go       # relay
npm run test:rust     # WASM renderer
npm run test:lua      # busted, if installed
npm run check:types   # tsc --noEmit
```

Run the one your change touches, plus the Lua suite if the plugin surface
moved. [GitHub Actions](../.github/workflows/ci.yml) runs them on every push
and pull request to `main`.

Two more harnesses exist for the parts a unit test cannot reach:
[`relay-testing.md`](relay-testing.md) drives the relay's endpoints by hand to
pin a failure to one hop, and [`diff-harness.md`](diff-harness.md) benchmarks
and verifies the experimental line-diff transport.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a test in the matching suite, update the affected pages
   under `docs/`.
4. Open a PR with a clear description of what changed and why — and say which
   of the four components it touches.

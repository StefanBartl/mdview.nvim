# Development

End users need none of this — the relay binary and client bundle are downloaded
automatically on first use (see [Installation](installation.md)). This page is
for changing mdview itself.

## Clone

```bash
git clone https://github.com/StefanBartl/mdview.nvim
cd mdview.nvim
npm install
```

Then point your plugin manager at the checkout (lazy.nvim: `dir = "..."`).

## Toolchain

| Tool | Needed for | Install |
|---|---|---|
| Node.js 18+ | client bundle, tests, lint | https://nodejs.org |
| Go 1.22+ | relay binary (`native/server`) | https://go.dev/dl |
| Rust + `wasm32-unknown-unknown` | WASM renderer (`native/wasm-render`) | `rustup target add wasm32-unknown-unknown` |
| `wasm-pack` | packaging the WASM renderer for the client | `cargo install wasm-pack` |

Verify before building:

```bash
node --version && go version && cargo --version && wasm-pack --version
```

`wasm-pack` is the one that is usually missing — `npm run build` fails on its
very first step with `'wasm-pack' is not recognized ...` if it isn't on `PATH`.

## Build variants

Editing Lua only? Build nothing. Use the release binary and bundle
(variant A in [Installation](installation.md)) and just reload Neovim.

### B — locally built relay, release client

Only Go is required.

```bash
npm run build:go
```

Produces `native/server/mdview-server` (**no `.exe` suffix, also on Windows** —
the `-o` name is literal). Then:

```lua
require("mdview").setup({
  dev = { binary_path = "C:/repos/mdview.nvim/native/server/mdview-server" },
  standalone = { binary_path = "C:/repos/mdview.nvim/native/server/mdview-server" },
})
```

`dev.web_root` stays unset, so the client bundle still comes from the pinned
release. That is fine as long as your Go change doesn't depend on a matching
client change.

### C — full source build

Relay **and** client from source. Order matters: `build:client` imports
`src/client/wasm-render/mdview_wasm_render.js`, which only `build:wasm`
generates, so the client build fails outright without it.

```bash
npm run build:go     # -> native/server/mdview-server
npm run build        # build:wasm (wasm-pack) then build:client (vite) -> dist/client
```

**Zero config needed once built.** `:MDView start` and `:MDView standalone`
auto-detect a build sitting inside the plugin's own checkout —
`native/server/mdview-server` (Go keeps the exact `-o` name, so no `.exe` on
Windows) and `dist/client` — and use it ahead of the downloaded release. A
normal install never ships those (both are gitignored), so this only ever kicks
in on a dev checkout. So you usually **don't** need the `dev.*` /
`standalone.binary_path` overrides at all — they're only for pointing at a build
*outside* this checkout.

Let your plugin manager rebuild on update so the auto-detected build stays
current. With lazy.nvim:

```lua
{
  "StefanBartl/mdview.nvim",
  build = "npm ci && npm run build:go && npm run build",
  -- no dev.*/standalone.binary_path needed — the build is auto-detected
}
```

`build` runs on `:Lazy install` / `:Lazy update` / `:Lazy build` (not on every
startup — a source build needs the Go/Rust/Node toolchains and would be far too
slow to gate editor startup on). After a manual `git pull`, run `:Lazy build`
(or `npm run build && npm run build:go`) to refresh.

If you *do* want an explicit override (a build outside the checkout):

```lua
require("mdview").setup({
  dev = {
    binary_path = "C:/repos/mdview.nvim/native/server/mdview-server",
    web_root = "C:/repos/mdview.nvim/dist/client",
  },
  standalone = { binary_path = "C:/repos/mdview.nvim/native/server/mdview-server" },
})
```

Both build outputs are gitignored, so a fresh clone never has them.

### Live client development

```bash
npm run dev   # Go relay (port 43219) + Vite dev server (port 43220), concurrently
```

Vite proxies `/ws`, `/update` and `/health` to the relay, so the client hot-reloads
while the relay keeps running. `build:wasm` must have run at least once first.

## Overriding without touching your Lua config

`scripts/minimal_init.lua` and detached instances load none of your user config,
so the same two overrides exist as environment variables — used only when the
corresponding `dev.*` key is unset:

```bash
MDVIEW_DEV_BINARY=/path/to/mdview-server
MDVIEW_DEV_WEB_ROOT=/path/to/dist/client
```

## Troubleshooting

| Symptom | Cause |
|---|---|
| `failed to resolve mdview-server binary: dev.binary_path is not executable: <path>` | `dev.binary_path` points at something that isn't there — stale path, wrong drive, or `.exe` appended to a Go build that has no suffix. Overrides never fall back to the release. |
| `failed to resolve mdview client bundle: dev.web_root is not a directory: <path>` | `dist/client` was never built (`npm run build`) or the path is stale. |
| `'wasm-pack' is not recognized` | `cargo install wasm-pack` (and `rustup target add wasm32-unknown-unknown`). |
| `Cannot find module './wasm-render/mdview_wasm_render.js'` | `build:client` ran without `build:wasm`. Use `npm run build`. |
| `:MDView standalone` reports no `--watch` support | The relay is older than v0.3.0 — bump `install.version` or point `standalone.binary_path` at a local build. |

`:checkhealth mdview` and `:MDView diagnostics` show which binary and web root
are actually in use.

## Tests

```bash
npm test              # client (vitest)
npm run test:go       # relay
npm run test:rust     # WASM renderer
npm run test:lua      # busted, if installed
npm run check:types   # tsc --noEmit
npm run lint
```

**Contributions are welcome** – whether it's a bugfix, optimization, or new feature idea.

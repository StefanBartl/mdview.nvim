# Development

To develop or contribute:

1. Clone the repository:

```bash
git clone https://github.com/StefanBartl/mdview.nvim
cd mdview.nvim
```

2. Load manually or via your preferred plugin manager.

3. Development requires Node.js 18+, Go 1.22+, and Rust with the
   `wasm32-unknown-unknown` target (`rustup target add wasm32-unknown-unknown`)
   plus [`wasm-pack`](https://rustwasm.github.io/wasm-pack/installer/).
   End users don't need any of this — the release binary and client bundle
   are downloaded automatically on first use.

```bash
npm install
npm run build   # builds the WASM render module + client bundle
npm run dev     # runs the Go relay + Vite dev server together
```

4. Make changes, test (`npm test`, `npm run test:go`, `npm run test:rust`,
   `npm run test:lua`), and submit pull requests or open issues.

**Contributions are welcome** – whether it's a bugfix, optimization, or new feature idea.

## Running your local build inside Neovim

`:MDView start` normally runs the **downloaded release** pinned by
`install.version` (default `v0.2.0`) — not your working tree. So a feature that
isn't in that tagged release yet (for example the `/control` channel behind
`:MDView overlay` / `:MDView zoom` / `:MDView cursor`, added after `v0.2.0`)
does nothing: the command posts to a route the old relay doesn't have, the POST
is fire-and-forget, and you see no error and no effect while scroll sync (an
older feature that _is_ in the release) keeps working.

To make `:MDView start` run your locally built relay + client bundle instead,
build both and point mdview at them via `dev`:

```bash
npm run build      # WASM render module + client bundle -> dist/client
npm run build:go   # relay binary -> native/server/mdview-server(.exe)
```

```lua
require("mdview").setup({
  dev = {
    binary_path = "E:/repos/mdview.nvim/native/server/mdview-server.exe",
    web_root    = "E:/repos/mdview.nvim/dist/client",
  },
})
```

Both fall back to the `MDVIEW_DEV_BINARY` / `MDVIEW_DEV_WEB_ROOT` environment
variables, so you can point at a build without editing `setup()`. Paths are
expanded (`~`, `$VAR`); a path that doesn't exist fails loudly instead of
silently falling back to the release. Rebuild (`npm run build` /
`npm run build:go`) and restart the session to pick up further changes.

`dev` is unrelated to `standalone.binary_path`, which only affects
`:MDView standalone`.

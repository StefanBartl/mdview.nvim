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

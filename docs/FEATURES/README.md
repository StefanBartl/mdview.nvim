# mdview.nvim features

mdview.nvim is a browser-based live Markdown preview: a Go relay streams raw
buffer text over WebSocket, and a Rust module compiled to WebAssembly renders
and sanitizes it entirely inside the browser tab. Four themes, roughly
following the four places a feature actually lives:

- [PREVIEW.md](PREVIEW.md) — getting a document on screen and keeping it in
  sync: starting/stopping a session, live push, scroll sync, standalone mode,
  the no-server preview tab, click-navigate, reverse scroll.
- [RENDERING.md](RENDERING.md) — what happens to the Markdown between "text
  in Neovim" and "HTML in the browser": the comrak/ammonia pipeline, themes,
  code highlighting, local image assets, private blocks, blank-line handling.
- [SECURITY.md](SECURITY.md) — the trust boundary: loopback-only binding,
  per-session tokens, Origin checks, and the sanitizer as the second half of
  that boundary.
- [OPERATIONS.md](OPERATIONS.md) — everything for running and debugging a
  session day to day: installation/asset download, logging, diagnostics,
  breadcrumbs, `:checkhealth`.

See [docs/commands.md](../commands.md) / [docs/BINDINGS.md](../BINDINGS.md)
for the full `:MDView` subcommand reference and
[docs/architecture.md](../architecture.md) for how the four components
(Lua/Go/TypeScript/Rust) fit together.

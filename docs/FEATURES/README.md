# mdview.nvim features

mdview.nvim is a browser-based live Markdown preview: a Go relay streams raw
buffer text over WebSocket, and a Rust module compiled to WebAssembly renders
and sanitizes it entirely inside the browser tab.

**Start here: [FEATURES.md](FEATURES.md)** — the complete catalog, covering
both what a user operates and the machinery underneath (caches, throttling,
the diff transport, lifecycle rules). The four theme files below go into
depth on the big areas, in the
[`FEATURES_FORMAT`](https://github.com/StefanBartl/documentation.nvim/blob/main/docs/FEATURES_FORMAT.md)
shape (`## feature`, then `- **Key:** value` metadata):

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

Neighbouring folders: [`../ROADMAP/ROADMAP.md`](../ROADMAP/ROADMAP.md) (open
items), [`../ROADMAP/DONE.md`](../ROADMAP/DONE.md) (why things were built the
way they were), [`../ROADMAP/IDEAS/`](../ROADMAP/IDEAS/) (nothing planned, kept so it is not
lost).

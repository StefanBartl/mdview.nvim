# Ideas

What lies here is **not planned** — it is recorded so that it does not get
lost.

| Folder | What |
| --- | --- |
| **this one** | ideas with no near-term implementation: exotic, not yet made concrete, or deliberately deferred |
| [`../ROADMAP.md`](../ROADMAP.md) | open items that are concrete enough to be started |
| [`../DONE.md`](../DONE.md) | decision log: what was built and why that way |
| [`docs/FEATURES/`](../../FEATURES/) | the catalogue of what exists today |

The line against the roadmap: **could one start tomorrow?** If yes, it
belongs in `ROADMAP.md`. If design work, a matter of principle, or a concrete
case for it is still missing, it belongs here.

## Contents

- **[KONZEPT_overlays.md](KONZEPT_overlays.md)** — a generic, extensible
  overlay system over the preview (a floating TOC, a cursor magnifier,
  keycast) as one system instead of loose individual features. Parts of it
  exist by now (`src/client/render/overlays/`), the overall concept is open.
- **[KONZEPT_links_und_cursor.md](KONZEPT_links_und_cursor.md)** — link
  behaviour in the preview tab, and the cursor overlay. The link part is
  largely implemented by now (`externalLinks.ts`, `clickNav.ts`,
  `linkHover.ts`); the cursor overlay stages are not.
- **[KONZEPT_headless_und_standalone.md](KONZEPT_headless_und_standalone.md)** —
  a preview without a running Neovim instance. `:MDView standalone` covers
  the main case; the further stages are open.

> These three documents are older than the Go/Rust rewrite and name endpoints
> that no longer exist in places (e.g. `/render?key=`). As ideas they remain
> valid; the implementation follows today's architecture.

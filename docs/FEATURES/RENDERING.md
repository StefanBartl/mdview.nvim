# Rendering

What happens to the Markdown text between "buffer content in Neovim" and
"HTML on screen in the browser" — all of it client-side, all of it in the
Rust/WASM module.

## Sanitized Markdown rendering (comrak + ammonia)

Markdown is parsed with `comrak` (GFM tables, strikethrough, autolink,
tasklists, footnotes) and rendered to HTML, then passed through an
`ammonia` allowlist sanitizer before it ever touches the DOM — rendering and
sanitization happen as one inseparable WASM call, so no caller can get HTML
that skipped the allowlist. Raw HTML embedded in the Markdown source is
parsed into the tree (not merely escaped) specifically so it goes through the
same sanitization pass as generated markup, rather than being a second,
unsanitized path into the page.

- **Tab:** true
- **Module:** `native/wasm-render/src/lib.rs` (`render_markdown`, `build_options`, `sanitizer`)
- **Config:** `install.version` pins which relay/renderer build ships; see [../architecture.md](../architecture.md)

### What the allowlist actually permits

The sanitizer starts from ammonia's default (safe) allowlist and adds exactly
four things, each for a specific rendering feature and each verified inert by
a dedicated test in `native/wasm-render/src/lib.rs`:

- `<input type="checkbox" checked disabled>` — GFM task-list checkboxes.
  Only `type`/`checked`/`disabled` are allowed on `<input>`, so an attacker
  supplying `<input type="text" formaction="javascript:...">` still gets
  `formaction` and `onfocus` stripped — the allowlist is per-attribute per-tag,
  not "trust `<input>`".
- `<span data-sp="…">` — inline source-position wrappers used for the exact
  cursor caret (see "Neovim cursor marker" in [PREVIEW.md](PREVIEW.md)).
- `<div data-private>` — the private-block container (see below).
- `class="language-xxx"` on `<code>` — otherwise silently stripped by
  ammonia's default (which has no attributes at all for `<code>`), which
  starved the client-side highlighters of the language hint they read to pick
  a grammar. Only `class` is allowed there, not arbitrary attributes.

`<script>`, event-handler attributes (`onerror`, `onclick`, …), `javascript:`
URLs, `<iframe>`, and `<object>` are all stripped regardless of source —
whether they arrived as Markdown-embedded raw HTML or as generated markup.

### Source-position mapping

Every block element carries `data-sourcepos="startLine:col-endLine:col"` so
the client can map a Neovim cursor line to the matching DOM node (scroll sync)
and, when the cursor marker mode is `"caret"`, individual inline text/code
runs are additionally wrapped in `<span data-sp="…">` carrying byte-accurate
columns — matching Neovim's own byte-based column numbering, including for
multi-byte UTF-8 text. Image `alt` text and the contents of fenced code
blocks are deliberately left unwrapped (an `alt=""` attribute or a
client-side syntax highlighter would mangle injected spans).

- **Module:** `native/wasm-render/src/lib.rs` (`annotate_source_positions`)

## Private blocks

A fenced code block with the info string `private` (` ```private `) is
rendered as a blurred-by-default container instead of a code block — its
contents are rendered as normal Markdown (not shown as escaped code) so
formatting still works, just visually hidden until revealed. Meant for
hiding third-party names, credentials-adjacent text, or numbers during a
screen share without keeping them in a separate file.

- **Module:** `native/wasm-render/src/lib.rs` (`transform_private_blocks`)
- **Usercmds:** `:MDView reveal [on|off|toggle]` toggles `.mdview-reveal-all` on the whole preview; individual blocks also reveal on click

## Local image asset serving

The renderer already produces correct `<img>` markup for `![alt](path)` —
the actual gap is resolution: a relative `src` resolves against the
*browser page's* URL, not the previewed document's directory on disk, and
the relay's static file server is rooted at the client bundle, not the
document. `GET /asset?key=&path=&token=` closes that gap: `path` is resolved
and clamped to the directory recorded for that document's room (which comes
only from the trusted local Neovim process, never from the browser), plus an
image-extension allowlist. `http(s)://` and `data:` sources are left
untouched.

- **Module:** `src/client/render/localImages.ts`, `native/server/main.go` (`handleAsset`), `native/server/internal/relay/registry.go` (`SetDocDir`/`DocDir`)

## Themes

Five bundled preview themes (`github`, `dark-dimmed`, `plain`, `tokyonight`,
`catppuccin`), each optionally suffixed `-light`/`-dark` to pin the color
scheme rather than follow the browser/OS preference. Switchable at runtime
without reopening the tab.

- **Module:** `src/client/themes/*.css`, `lua/mdview/bindings/usrcmds/theme.lua`
- **Usercmds:** `:MDView theme [name]` (no argument reports the current theme)
- **Config:** `browser.theme` (default `"github"`)

## Code-fence syntax highlighting

Client-side, lazy-loaded, and swappable at four cost/fidelity levels:
`hljs` (highlight.js, light, the default), `shiki` (exact TextMate/VSCode
grammars matching the tokyo-night/catppuccin/dark-plus themes, heavier),
`nvim` (see below), or `none`.

- **Module:** `src/client/highlight/hljs.ts`, `src/client/highlight/shiki.ts`
- **Config:** `browser.highlighter` (default `"hljs"`)

### `nvim` — the buffer's own colors

`browser.highlighter = "nvim"` stops guessing the language in the browser and
paints code blocks with **the colors Neovim is already showing**. The preview
and the buffer next to it then agree by construction rather than by
coincidence: same colorscheme, same highlight groups, and a `:colorscheme`
change in Neovim reaches the browser with the next push.

The colors come from [color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim)
through its public read-back API (`color_my_ascii.highlight`), which returns
the spans it painted plus their resolved `#rrggbb`. mdview collects them per
fenced block and pushes them over `/spans` — a channel of its own, stored by
the relay rather than ephemeral, so a reloaded tab is repainted immediately
instead of sitting unhighlighted until the next edit.

**A block Neovim did not paint goes to highlight.js**, not to a flat gray box.
That is the normal case, not an edge case: color_my_ascii's `fence_language_map`
covers 31 fence tags, highlight.js knows around 190 languages. So `nvim` is an
*addition* to the JavaScript highlighter for the languages both know, never a
replacement that loses coverage — a document with ```lua and ```yaml blocks gets
the first from Neovim and the second from highlight.js, in one page.

color_my_ascii stays a **soft** dependency: without it there are no spans, the
payload is empty, and every block falls through exactly as it did before.

- **Module:** `lua/mdview/core/fence_spans.lua`, `src/client/highlight/nvim.ts`
- **Config:** `browser.highlighter = "nvim"`

## Blank-line handling

CommonMark's default collapses any run of blank lines between blocks to a
single paragraph gap; `preserve_blank_lines` opts out and shows every blank
line as its own extra vertical space instead — useful for documents where
spacing itself is meaningful. Toggles live, no reload.

- **Module:** `src/client/render/blankLines.ts`, `lua/mdview/bindings/usrcmds/blanklines.lua`
- **Usercmds:** `:MDView blanklines [on|off|toggle]`
- **Config:** `browser.preserve_blank_lines` (default `false`)

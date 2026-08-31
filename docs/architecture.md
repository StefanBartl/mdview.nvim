# Architecture

| Component         | Technology              | Description                                                          |
| ----------------- | ----------------------- | ---------------------------------------------------------------------|
| **Core**          | Lua (+ [lib.nvim](https://github.com/StefanBartl/lib.nvim)) | Handles Neovim buffer events, state management, IPC   |
| **Server**        | Go                      | Loopback-only relay: file/buffer text in, WebSocket fan-out — no HTML. Also serves local image bytes for the currently-previewed document (`/asset`, see below) — the one place it touches a file's raw contents rather than just text/bytes handed to it directly |
| **Client**        | TypeScript              | Thin WebSocket glue + DOM injection of already-sanitized HTML        |
| **Communication** | WebSocket               | Buffer text in, sanitized HTML never leaves the browser               |
| **Rendering**     | Rust → WASM (comrak + ammonia) | Markdown → HTML + allowlist sanitization, both in the browser  |

## Content sources

The relay knows nothing about files or buffers — it only knows *"here is text
for room K, fan it out"*. Everything downstream of that (WebSocket framing, the
client, the WASM renderer) is reached through one code path regardless of where
the text came from. That leaves room for exactly two producers:

| Source | Driven by | Reaches the relay via |
| --- | --- | --- |
| Neovim buffer | `:MDView start` | `POST /update` (token-gated), on every buffer change |
| File on disk | `:MDView standalone`, `mdview-server --watch` | `internal/source`, polling the file and calling `registry.Broadcast` in-process |

Because both converge on the same `Broadcast`, standalone mode is not a second
implementation of the preview — it's the same preview with a different producer.
The security model is unchanged either way (loopback-only bind, per-session
token, Origin check); only *who generates the token* differs, since in
standalone mode there is no Lua side to do it.

See [standalone.md](standalone.md) for the user-facing side of this.

Beside the content there are **sidecar channels**, each a POST from Neovim that
the relay forwards verbatim without inspecting it: `/scroll` (cursor position),
`/doc` (which document is shown), `/control` (live preview settings, capped at
1 KiB), and `/spans` (the buffer's own fence highlighting, for
`browser.highlighter = "nvim"`).

`/spans` is the one exception to "sidecars are ephemeral". The others carry a
passing event that the next one supersedes; fence highlighting describes the
current document, so the relay stores the last one per room alongside — never
instead of — the content, and seeds a joining tab with both. Without that, a
reloaded tab would show the content unhighlighted until the next edit arrived.

See [FEATURES/RENDERING.md](FEATURES/RENDERING.md#nvim--the-buffers-own-colors)
and [FEATURES/PREVIEW.md](FEATURES/PREVIEW.md#visual-selection-mirror).

## Local image assets

The WASM renderer produces correct `<img>` markup for `![alt](path)` on its
own (`comrak`, no custom code needed) — the gap was resolution, not
rendering: a relative `src` resolves against the *page's* URL in the
browser, not the document's directory on disk, and the plain
`http.FileServer` mentioned above is rooted at the client bundle, never the
document.

`GET /asset?key=&path=&token=` closes that gap: `path` is resolved and
clamped to the directory `handleDoc` records per session (`Registry.
SetDocDir`/`DocDir`) — that base directory comes only from the trusted
local Neovim process (the body of every `/doc` call), never from the
browser tab, which only ever supplies the relative `path`. A path-traversal
containment check plus an image-extension allowlist (matching images.nvim's
own list) keep the route narrowly scoped, not a general file server.
`src/client/render/localImages.ts` rewrites relative `<img src>` to this
route after each render, the same lifecycle `markExternalLinks` already
uses for links; `http(s)://`/`data:` sources are left untouched.

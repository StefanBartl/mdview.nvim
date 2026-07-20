# Architecture

| Component         | Technology              | Description                                                          |
| ----------------- | ----------------------- | ---------------------------------------------------------------------|
| **Core**          | Lua (+ [lib.nvim](https://github.com/StefanBartl/lib.nvim)) | Handles Neovim buffer events, state management, IPC   |
| **Server**        | Go                      | Loopback-only relay: file/buffer text in, WebSocket fan-out — no HTML |
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
| Neovim buffer | `:MDView start` / `:MDView detach` | `POST /update` (token-gated), on every buffer change |
| File on disk | `:MDView standalone`, `mdview-server --watch` | `internal/source`, polling the file and calling `registry.Broadcast` in-process |

Because both converge on the same `Broadcast`, standalone mode is not a second
implementation of the preview — it's the same preview with a different producer.
The security model is unchanged either way (loopback-only bind, per-session
token, Origin check); only *who generates the token* differs, since in
standalone mode there is no Lua side to do it.

See [standalone.md](standalone.md) for the user-facing side of this.

# Architecture

| Component         | Technology              | Description                                                          |
| ----------------- | ----------------------- | ---------------------------------------------------------------------|
| **Core**          | Lua (+ [lib.nvim](https://github.com/StefanBartl/lib.nvim)) | Handles Neovim buffer events, state management, IPC   |
| **Server**        | Go                      | Loopback-only relay: file/buffer text in, WebSocket fan-out — no HTML |
| **Client**        | TypeScript              | Thin WebSocket glue + DOM injection of already-sanitized HTML        |
| **Communication** | WebSocket               | Buffer text in, sanitized HTML never leaves the browser               |
| **Rendering**     | Rust → WASM (comrak + ammonia) | Markdown → HTML + allowlist sanitization, both in the browser  |

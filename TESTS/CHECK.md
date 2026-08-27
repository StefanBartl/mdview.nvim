# Manual test tasks (in a real Neovim)
[testlink](.\docs\PoC.md)
1. `browser.behavior`: test with two MD files — `reuse` (one tab follows), `new_tab`, `manual`.
    **Enable the opt-in features one by one** (`setup({ experimental = { … = true } })`)
1. `click_navigate = true` → click a relative link `[x](other.md)` → nvim opens `other.md`, the preview follows.
2. `reverse_scroll = true` → scroll in the browser → the nvim cursor follows (with ~250 ms lag, now `transport.inbound_poll_ms` — **please judge here whether it "feels ok"**, that could not be assessed headless; if it does not, that key is the dial).
3. `webtransport = true` → should fall back to WebSocket transparently (no HTTP/3 backend), the preview works normally.
    **Cross-platform (if possible)**
1. Test `:MDViewStart` once on Linux — the shim should catch the lib.nvim bug; once lib.nvim itself is fixed, the shim can go.

---

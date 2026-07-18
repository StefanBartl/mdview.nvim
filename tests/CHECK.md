# Test-Tasks für dich (manuell, im echten Neovim)
[testlink](.\docs\PoC.md)
1. `browser.behavior`: mit zwei MD-Dateien testen — `reuse` (ein Tab folgt), `new_tab`, `manual`.
    **Opt-in-Features einzeln aktivieren** (`setup({ experimental = { … = true } })`)
1. `click_navigate = true` → auf einen relativen Link `[x](other.md)` klicken → nvim öffnet `other.md`, Preview folgt.
2. `reverse_scroll = true` → im Browser scrollen → nvim-Cursor folgt (mit ~250 ms Lag — **hier bitte auf „fühlt sich ok an" achten**, das konnte ich headless nicht beurteilen).
3. `webtransport = true` → sollte transparent auf WebSocket zurückfallen (kein HTTP/3-Backend), Preview funktioniert normal.
    **Cross-Platform (falls möglich)**
1. Einmal auf Linux `:MDViewStart` testen — mein Shim sollte den lib.nvim-Bug abfangen; wenn du lib.nvim selbst fixt, kann der Shim später raus.

---


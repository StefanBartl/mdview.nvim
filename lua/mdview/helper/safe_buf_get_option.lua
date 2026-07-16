---@module 'mdview.helper.safe_buf_get_option'
-- Backwards-compatible helper to read buffer-local options.
-- Re-exports lib.nvim.buf_win_tab.get_option, which does the same
-- multi-API-variant fallback chain (nvim_get_option_value ->
-- nvim_buf_get_option -> current-buffer vim.bo -> nvim_buf_call + vim.bo),
-- each pcall-guarded, just tried in modern-first rather than legacy-first
-- order — the two converge on the same result either way.

return require("lib.nvim.buf_win_tab.get_option")

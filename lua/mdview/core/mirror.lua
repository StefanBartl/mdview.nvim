---@module 'mdview.core.mirror'
--- Single entry point for the buffer text that goes into the preview.
---
--- Every place that reads a buffer in order to *show it in the preview*
--- (live push, BufEnter snapshot, buffer switch, initial push, the preview
--- tab, the push helpers in core/events) goes through `M.lines`. A transform
--- (for example a translation for a different display language) can then be
--- hooked in at exactly this one place instead of at each call site; a site
--- that was forgotten would silently show the untransformed text.
---
--- Documented exceptions that deliberately keep reading the REAL buffer with
--- `nvim_buf_get_lines` (the guard spec TESTS/nvim/mirror_guard_spec.lua
--- lists them and fails on any other use under lua/mdview):
---
---   * adapter/inbound_poll.lua -- the reverse direction (browser -> buffer:
---     checkbox toggle, text-field sync). It must read and patch the text the
---     user actually edits; a transformed copy would write wrong text back.
---   * core/breadcrumbs.lua -- computes the heading trail up to the cursor
---     line of the real buffer (a ranged read, not content for the preview).
---   * test/runner.lua -- the in-editor test runner reads the buffer under test.
---
--- Future asynchronous variant: `M.lines_async(bufnr, cb)` is the slot for a
--- transform that cannot answer synchronously. For now it calls back at once
--- with the synchronous result, so callers can already be written against it.

local api = vim.api

local M = {}

--- Buffer text as the preview should show it (today: the buffer text as is).
--- Always returns a fresh table the caller may mutate.
---@param bufnr integer
---@return string[] lines
function M.lines(bufnr)
  return api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
end

--- Asynchronous variant (placeholder for transforms that need time).
--- Currently invokes `cb` synchronously with `M.lines(bufnr)`.
---@param bufnr integer
---@param cb fun(lines: string[])
---@return nil
function M.lines_async(bufnr, cb)
  cb(M.lines(bufnr))
end

return M

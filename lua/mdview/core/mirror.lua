---@module 'mdview.core.mirror'
--- Single entry point for the text that goes into the preview.
---
--- Every place that reads a buffer, or a file that is not open in one, in order
--- to *show it in the preview* (live push, BufEnter snapshot, buffer switch,
--- initial push, the preview tab, the push helpers in core/events) goes through
--- `M.lines` / `M.lines_for_path`. A transform (for example a translation for a
--- different display language) can then be hooked in at exactly this one place
--- instead of at each call site; a site that was forgotten would silently show
--- the untransformed text.
---
--- A buffer that is not loaded (`nvim a.md b.md`, `:bunload`, `:badd`) has no
--- text in memory: the buffer API answers an empty list for it, without
--- raising. Such a buffer shows what is on disk instead, never an empty
--- document.
---
--- Documented exceptions that deliberately keep reading the REAL buffer with
--- `nvim_buf_get_lines` (the guard spec TESTS/nvim/mirror_guard_spec.lua
--- lists them and fails on any other use of `nvim_buf_get_lines` or `readfile`
--- under lua/mdview):
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

--- A file as the preview shows it, read from disk. An empty, missing or
--- unreadable path is a document with nothing to show (`{}`), not an error:
--- `readfile` raises for those, so it is wrapped.
---@internal
---@param path string
---@return string[] lines
local function read_disk(path)
  if path == "" then
    return {}
  end
  local ok, content = pcall(vim.fn.readfile, path)
  if ok and type(content) == "table" then
    return content
  end
  return {}
end

--- Buffer text as the preview should show it (today: the buffer text as is; for
--- a buffer that is not loaded, the file on disk). Always returns a fresh table
--- the caller may mutate. An invalid buffer handle still raises, as the buffer
--- API does.
---@param bufnr integer
---@return string[] lines
function M.lines(bufnr)
  if api.nvim_buf_is_loaded(bufnr) then
    return api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end
  return read_disk(api.nvim_buf_get_name(bufnr))
end

--- Text of the document at `path` as the preview should show it: the buffer
--- that has the file open (unsaved edits included) when there is one, otherwise
--- the file on disk. `{}` when the path is neither. Always a fresh table.
---@param path string
---@return string[] lines
function M.lines_for_path(path)
  if type(path) ~= "string" or path == "" then
    return {}
  end
  local bufnr = vim.fn.bufnr(path, false)
  if bufnr ~= -1 then
    return M.lines(bufnr)
  end
  return read_disk(path)
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

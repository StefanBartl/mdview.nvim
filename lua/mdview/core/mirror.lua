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
--- Everything else under lua/mdview stays away from the raw read routes (a
--- buffer's lines or text, a file's lines or bytes). The guard spec
--- TESTS/nvim/mirror_guard_spec.lua lists the forbidden routes and fails on any
--- use outside the documented exceptions. An exception is granted per route,
--- never per file: a file that may read the real buffer may not read a file
--- from disk because of that, and the other way round.
---
--- Documented exceptions, which deliberately keep reading the REAL buffer with
--- `nvim_buf_get_lines`:
---
---   * adapter/inbound_poll.lua -- the reverse direction (browser -> buffer:
---     checkbox toggle, text-field sync). It must read and patch the text the
---     user actually edits; a transformed copy would write wrong text back.
---   * core/breadcrumbs.lua -- computes the heading trail up to the cursor
---     line of the real buffer (a ranged read, not content for the preview).
---   * test/runner.lua -- the in-editor test runner reads the buffer under test.
---
--- Documented exception for reading a file with `io.open` in read mode (the
--- content is not preview text):
---
---   * adapter/install.lua -- hashes the downloaded server binary and reads the
---     checksum list that belongs to it.
---
--- The asynchronous variants (`M.lines_async`, `M.lines_for_path_async`) hand the
--- text to the display transform (core/display.lua) before it reaches the
--- preview; they are what the push paths use.

local normkey = require("lib.nvim.fs.normkey")

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

--- The last path component in lower case, whichever separator precedes it. A
--- cheap superset test: two spellings of one file end in the same component, so
--- a buffer that fails it need not be looked at any closer.
---@internal
---@param name string
---@return string
local function tail_of(name)
  return (name:match("[^/\\]*$"):lower())
end

--- Comparison key of an absolute file name: one separator style, a Windows
--- drive letter in one case, symlinks and 8.3 short names resolved; the case of
--- the name does not count when the editor ignores it for file names.
---@internal
---@param abs string
---@return string
local function key_of(abs)
  local key = normkey(abs)
  if vim.o.fileignorecase then
    key = key:lower()
  end
  return key
end

--- The loaded buffer that has exactly the file `abs` open, or nil. Compares
--- names, never patterns: `vim.fn.bufnr()` reads its argument as a file pattern
--- that also matches inside a buffer name (`a.md` finds `other/a.md`, `xa.md`,
--- `a.md.bak`), and `[ { ~ * ? % #` in a file name are pattern syntax (`%` is
--- the current buffer). A buffer that is not loaded does not count: it has no
--- text of its own, its file on disk is the answer.
---@internal
---@param abs string # absolute, as `fnamemodify(path, ":p")` makes it
---@return integer|nil bufnr
local function loaded_buffer_of(abs)
  local tail = tail_of(abs)
  if tail == "" then
    return nil -- a directory
  end
  local key
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) then
      local name = api.nvim_buf_get_name(buf)
      if name ~= "" and tail_of(name) == tail then
        key = key or key_of(abs)
        if key_of(name) == key then
          return buf
        end
      end
    end
  end
  return nil
end

--- Text of the document at `path` as the preview should show it: the buffer
--- that has exactly this file open (unsaved edits included) when there is one,
--- otherwise the file on disk. `{}` when the path is neither. Always a fresh
--- table. A relative `path` is relative to the cwd, as `:MDView start a.md`
--- passes it on as typed.
---@param path string
---@return string[] lines
function M.lines_for_path(path)
  if type(path) ~= "string" or path == "" then
    return {}
  end
  local ok, abs = pcall(vim.fn.fnamemodify, path, ":p")
  if not ok or type(abs) ~= "string" or abs == "" then
    return {}
  end
  local bufnr = loaded_buffer_of(abs)
  if bufnr then
    return M.lines(bufnr)
  end
  return read_disk(abs)
end

--- Asynchronous variant: the display transform (`mdview.core.display`, the
--- display language and `browser.transform`) sits behind it. `cb(lines, final)`
--- runs once and synchronously when no transform is configured, so a plain
--- session behaves as with `M.lines`; with one it may run several times (a first
--- valid text, patches while paragraphs are translated, the finished document),
--- every text with as many lines as the buffer. A result that went stale (a newer
--- push into the same `opts.target` room, a buffer or tab switch) is never
--- delivered.
---@param bufnr integer
---@param cb fun(lines: string[], final: boolean, original: string[])
---@param opts { target?: string, path?: string, reason?: string }|nil
---   target: room the text goes to (default: the buffer name);
---   path: source document (default: the buffer name);
---   reason: "edit"|"save"|"switch"|"initial"|"enable"|"refresh" (default "edit")
---@return boolean transformed # false: `cb` ran synchronously with the plain text
function M.lines_async(bufnr, cb, opts)
  opts = opts or {}
  local name = api.nvim_buf_get_name(bufnr)
  local original = M.lines(bufnr)
  return require("mdview.core.display").stream(
    {
      path = opts.path or name,
      target = opts.target or name,
      bufnr = bufnr,
      reason = opts.reason,
    },
    original,
    function(out, final)
      cb(out, final, original)
    end
  )
end

--- `M.lines_for_path` through the display transform, like `M.lines_async`.
---@param path string
---@param cb fun(lines: string[], final: boolean, original: string[])
---@param opts { target?: string, reason?: string }|nil
---@return boolean transformed
function M.lines_for_path_async(path, cb, opts)
  opts = opts or {}
  local original = M.lines_for_path(path)
  return require("mdview.core.display").stream(
    {
      path = path,
      target = opts.target or path,
      reason = opts.reason,
    },
    original,
    function(out, final)
      cb(out, final, original)
    end
  )
end

return M

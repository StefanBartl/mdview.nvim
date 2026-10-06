---@module 'tests.nvim.mirror_unloaded_spec'
-- core/mirror must never answer "empty document" for a buffer that merely is not
-- loaded. nvim_buf_get_lines does not raise on such a buffer, it returns {}, so
-- before the fix `:MDView start b.md` (b.md opened as `nvim a.md b.md`, or
-- `:bunload`ed) seeded the preview with an empty document and the disk fallback
-- in the start command was never reached. A buffer that is not loaded shows
-- what is on disk; a loaded one shows its (possibly unsaved) text.

---@diagnostic disable: undefined-global

local mirror = require("mdview.core.mirror")
local normalize = require("mdview.helper.normalize")

---@param path string
---@return nil
local function wipe_buffers_of(path)
  local want = vim.fs.normalize(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fs.normalize(vim.api.nvim_buf_get_name(b)) == want then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

--- Runs `fn(path)` with a temporary markdown file holding `content`; the file and
--- every buffer created for it are removed even when an assertion in `fn` throws.
---@param content string[]
---@param fn fun(path: string)
---@return nil
local function with_file(content, fn)
  local path = vim.fn.tempname() .. ".md"
  vim.fn.writefile(content, path)
  local ok, err = pcall(fn, path)
  wipe_buffers_of(path)
  vim.fn.delete(path)
  if not ok then
    error(err, 0)
  end
end

describe("mdview.core.mirror with a buffer that is not loaded", function()
  it("lines() answers the file on disk for a known-but-unloaded buffer, not {}", function()
    with_file({ "# on disk", "line two" }, function(path)
      local buf = vim.fn.bufadd(path)
      assert.is_false(vim.api.nvim_buf_is_loaded(buf))
      assert.are.same({ "# on disk", "line two" }, mirror.lines(buf))
    end)
  end)

  it("lines() answers the file on disk after the buffer was :bunload-ed", function()
    with_file({ "# first", "second" }, function(path)
      -- Loaded first, then unloaded: the state `nvim a.md b.md` + `:bunload b` leaves behind.
      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      assert.is_true(vim.api.nvim_buf_is_loaded(buf))
      vim.cmd("bunload " .. buf)
      assert.is_false(vim.api.nvim_buf_is_loaded(buf))
      assert.are.same({ "# first", "second" }, mirror.lines(buf))
    end)
  end)

  it("lines() is {} for an unloaded buffer whose file does not exist (a :badd of a new name)", function()
    local path = vim.fn.tempname() .. "-not-there.md"
    local buf = vim.fn.bufadd(path)
    local ok, got = pcall(mirror.lines, buf)
    wipe_buffers_of(path)
    assert.is_true(ok, tostring(got))
    assert.are.same({}, got)
  end)

  it("lines() is {} for an unloaded buffer without a name", function()
    local buf = vim.fn.bufadd("")
    local ok, got = pcall(mirror.lines, buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(ok, tostring(got))
    assert.are.same({}, got)
  end)

  it("lines() still returns the (unsaved) buffer text once the buffer is loaded", function()
    with_file({ "# on disk" }, function(path)
      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# edited, not saved" })
      assert.are.same({ "# edited, not saved" }, mirror.lines(buf))
    end)
  end)
end)

describe("mdview.core.mirror.lines_for_path", function()
  it("answers the file on disk when no buffer knows the path", function()
    with_file({ "# no buffer", "just a file" }, function(path)
      assert.are.same({ "# no buffer", "just a file" }, mirror.lines_for_path(normalize.path(path)))
    end)
  end)

  it("answers the file on disk for a known-but-unloaded buffer (the `:MDView start b.md` case)", function()
    with_file({ "# b on disk", "text" }, function(path)
      vim.fn.bufadd(path)
      assert.are.same({ "# b on disk", "text" }, mirror.lines_for_path(normalize.path(path)))
    end)
  end)

  it("answers the unsaved buffer text for a loaded buffer, not the stale disk text", function()
    with_file({ "# on disk" }, function(path)
      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# edited", "unsaved" })
      assert.are.same({ "# edited", "unsaved" }, mirror.lines_for_path(normalize.path(path)))
    end)
  end)

  it("is {} for a path that is neither a buffer nor a readable file", function()
    local path = normalize.path(vim.fn.tempname() .. "-missing.md")
    assert.are.same({}, mirror.lines_for_path(path))
  end)

  it("is {} for an empty path instead of raising", function()
    assert.are.same({}, mirror.lines_for_path(""))
  end)

  it("returns a fresh table on every call", function()
    with_file({ "a", "b" }, function(path)
      local norm = normalize.path(path)
      local first = mirror.lines_for_path(norm)
      first[1] = "mutated"
      assert.are.same({ "a", "b" }, mirror.lines_for_path(norm))
    end)
  end)
end)

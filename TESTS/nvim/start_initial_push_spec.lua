---@module 'tests.nvim.start_initial_push_spec'
-- `:MDView start <file>` seeds the preview with that file's content. The content
-- must be the file's real text in every state the buffer can be in: a loaded
-- buffer (unsaved edits included), no buffer at all, and -- the bug -- a buffer
-- the editor knows but has not loaded (`nvim a.md b.md`, `:bunload`, `:badd`).
-- There the buffer API answers {} without raising, so the preview used to be
-- seeded with an empty document and stayed blank until the next edit or save.
--
-- try_push is replaced so the pushed lines are observable instead of going to a
-- relay; initial_push_async is reachable through the test seam M._initial_push_async.

---@diagnostic disable: undefined-global

local start = require("mdview.bindings.usrcmds.start")
local normalize = require("mdview.helper.normalize")

local TRYPUSH = "mdview.bindings.usrcmds.start.server.try_push"

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

--- Runs `fn(path)` with a temporary markdown file; file and buffers are removed afterwards,
--- also when an assertion in `fn` throws.
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

describe("usrcmds.start initial push of an explicit file", function()
  local original, pushed

  before_each(function()
    original = package.loaded[TRYPUSH]
    pushed = nil
    package.loaded[TRYPUSH] = {
      try_push = function(path, lines)
        pushed = { path = path, lines = lines }
      end,
    }
  end)

  after_each(function()
    package.loaded[TRYPUSH] = original
  end)

  it("pushes the disk content of a buffer that is known but not loaded", function()
    with_file({ "# b.md", "content on disk" }, function(path)
      local buf = vim.fn.bufadd(path)
      assert.is_false(vim.api.nvim_buf_is_loaded(buf))
      start._initial_push_async("try_push", nil, nil, {}, path)
      assert(pushed, "try_push was not called")
      assert.are.same({ "# b.md", "content on disk" }, pushed.lines)
    end)
  end)

  it("pushes the disk content after the buffer was :bunload-ed", function()
    with_file({ "# unloaded", "still on disk" }, function(path)
      -- Loaded first, then unloaded: the state `nvim a.md b.md` + `:bunload b` leaves behind.
      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      assert.is_true(vim.api.nvim_buf_is_loaded(buf))
      vim.cmd("bunload " .. buf)
      assert.is_false(vim.api.nvim_buf_is_loaded(buf))
      start._initial_push_async("try_push", nil, nil, {}, path)
      assert(pushed, "try_push was not called")
      assert.are.same({ "# unloaded", "still on disk" }, pushed.lines)
    end)
  end)

  it("pushes the unsaved text of a loaded buffer, not the stale disk text", function()
    with_file({ "# on disk" }, function(path)
      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# edited", "unsaved" })
      start._initial_push_async("try_push", nil, nil, {}, path)
      assert(pushed, "try_push was not called")
      assert.are.same({ "# edited", "unsaved" }, pushed.lines)
    end)
  end)

  it("pushes the disk content when no buffer knows the file", function()
    with_file({ "# no buffer" }, function(path)
      start._initial_push_async("try_push", nil, nil, {}, path)
      assert(pushed, "try_push was not called")
      assert.are.same({ "# no buffer" }, pushed.lines)
    end)
  end)

  it("pushes under the normalized path", function()
    with_file({ "x" }, function(path)
      start._initial_push_async("try_push", nil, nil, {}, path)
      assert(pushed, "try_push was not called")
      assert.are.equal(normalize.path(path), pushed.path)
    end)
  end)

  it("pushes an empty document for a file that does not exist (nothing to show)", function()
    local path = vim.fn.tempname() .. "-gone.md"
    start._initial_push_async("try_push", nil, nil, {}, path)
    assert(pushed, "try_push was not called")
    assert.are.same({}, pushed.lines)
  end)
end)

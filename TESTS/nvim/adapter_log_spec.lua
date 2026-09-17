---@module 'tests.nvim.adapter_log_spec'
-- Verifies mdview.adapter.log: the relay-stdout ring buffer, its opt-in
-- persistent file logging (including the hand-rolled Windows-aware
-- ensure_dir/path_dirname pair that creates the log file's directory without
-- going through vim.fn.mkdir -- see the module's own comments on why: those
-- calls happen from the relay's stdout callback, a fast-event context where
-- vim.fn.* raises E5560), and M.show()'s scratch-buffer rendering.
--
-- ensure_dir's drive-letter branch (dir:match("^([A-Za-z]:)")) only actually
-- runs on Windows; the tests below use forward-slash absolute paths so the
-- same file exercises the real branch on whichever platform CI/the dev
-- machine happens to be.

---@diagnostic disable: undefined-global

local log = require("mdview.adapter.log")

-- Save/restore every override this module exposes -- it is a singleton
-- (required once, state lives in module-level locals), so leaking an
-- override here would affect every later spec that also requires it.
-- file_log_state() reports the EFFECTIVE state (override-or-config-default),
-- so capturing and replaying it puts later tests back on equivalent behavior
-- even though it can't distinguish "was overridden" from "was the default".
local function with_clean_overrides(fn)
  local enabled0, path0 = log.file_log_state()
  local ok, err = pcall(fn)
  log.set_file_log(enabled0)
  log.set_file_log_path(path0)
  log.setup({ debug = false })
  if not ok then
    error(err, 0)
  end
end

describe("adapter.log file-logging toggles", function()
  it("file_log_state defaults to config (off)", function()
    with_clean_overrides(function()
      log.set_file_log_path(nil)
      local enabled = select(1, log.file_log_state())
      assert.is_false(enabled)
    end)
  end)

  it("set_file_log overrides the config default and reports it back", function()
    with_clean_overrides(function()
      local enabled = log.set_file_log(true)
      assert.is_true(enabled)
      enabled = log.set_file_log(false)
      assert.is_false(enabled)
    end)
  end)

  it("toggle_file_log flips whatever the current state is", function()
    with_clean_overrides(function()
      log.set_file_log(false)
      local enabled = log.toggle_file_log()
      assert.is_true(enabled)
      enabled = log.toggle_file_log()
      assert.is_false(enabled)
    end)
  end)

  it("set_file_log_path(nil) falls back to config/default again", function()
    with_clean_overrides(function()
      log.set_file_log_path("/tmp/explicit-override.log")
      local _, path = log.file_log_state()
      assert.are.equal("/tmp/explicit-override.log", path)

      log.set_file_log_path(nil)
      local _, reset_path = log.file_log_state()
      assert.is_false(reset_path == "/tmp/explicit-override.log")
    end)
  end)

  it("setup({file_log=true, file_path=...}) sets both overrides at once", function()
    with_clean_overrides(function()
      log.setup({ file_log = true, file_path = "/tmp/setup-path.log" })
      local enabled, path = log.file_log_state()
      assert.is_true(enabled)
      assert.are.equal("/tmp/setup-path.log", path)
    end)
  end)
end)

describe("adapter.log.append persistent file writes", function()
  it("creates nested missing directories (ensure_dir) before writing", function()
    with_clean_overrides(function()
      local base = vim.fn.tempname()
      vim.fn.delete(base) -- tempname() also creates the file itself; start clean
      local nested = base .. "/a/b/c/relay.log"

      log.set_file_log(true)
      log.set_file_log_path(nested)
      log.append("hello from the nested-dir test")

      assert.are.equal(1, vim.fn.isdirectory(base .. "/a/b/c"))
      assert.are.equal(1, vim.fn.filereadable(nested))
      local lines = vim.fn.readfile(nested)
      assert.are.equal("hello from the nested-dir test", lines[1])

      vim.fn.delete(base, "rf")
    end)
  end)

  it("appends across repeated calls instead of truncating", function()
    with_clean_overrides(function()
      local path = vim.fn.tempname()
      log.set_file_log(true)
      log.set_file_log_path(path)
      log.append("line one")
      log.append("line two")

      local lines = vim.fn.readfile(path)
      assert.are.equal("line one", lines[1])
      assert.are.equal("line two", lines[2])

      vim.fn.delete(path)
    end)
  end)

  it("writes nothing to disk while file logging is off", function()
    with_clean_overrides(function()
      local base = vim.fn.tempname()
      vim.fn.delete(base)
      log.set_file_log(false)
      log.set_file_log_path(base .. "/should-not-appear.log")
      log.append("should not be written")
      assert.are.equal(0, vim.fn.filereadable(base .. "/should-not-appear.log"))
    end)
  end)
end)

describe("adapter.log ring buffer", function()
  it("splits a multi-line chunk into separate ring entries", function()
    local before = #log.lines()
    log.append("alpha\nbeta\ngamma")
    local after = log.lines()
    assert.are.equal(before + 3, #after)
    assert.are.equal("alpha", after[before + 1])
    assert.are.equal("beta", after[before + 2])
    assert.are.equal("gamma", after[before + 3])
  end)

  it("strips ANSI escape sequences before storing", function()
    local before = #log.lines()
    log.append("\27[31mred text\27[0m")
    local got = log.lines()[before + 1]
    assert.is_nil(got:find("\27", 1, true))
    assert.is_true(got:find("red text", 1, true) ~= nil)
  end)

  it("prepends an optional prefix", function()
    local before = #log.lines()
    log.append("payload", "[tag]")
    assert.are.equal("[tag] payload", log.lines()[before + 1])
  end)

  it("caps the ring at 2000 lines, dropping the oldest", function()
    -- Push well past the cap; the ring must never exceed it, and the
    -- earliest entries must be the ones that fell off.
    for i = 1, 2100 do
      log.append("filler-" .. i)
    end
    local lines = log.lines()
    assert.are.equal(2000, #lines)
    assert.are.equal("filler-2100", lines[#lines])
  end)

  it("ignores a nil line", function()
    local before = #log.lines()
    log.append(nil)
    assert.are.equal(before, #log.lines())
  end)
end)

describe("adapter.log.show scratch buffer", function()
  it("creates the mdview://logs buffer with the accumulated lines", function()
    log.append("shown-in-scratch-marker")
    log.show()
    vim.wait(50)

    local bufnr = vim.fn.bufnr("mdview://logs")
    assert(bufnr ~= -1, "expected the mdview://logs buffer to exist")
    local found = false
    for _, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if l == "shown-in-scratch-marker" then
        found = true
      end
    end
    assert.is_true(found)
    assert.are.equal("nofile", vim.bo[bufnr].buftype)
    assert.is_false(vim.bo[bufnr].modifiable)
  end)

  it("reuses the same buffer on a repeat call instead of erroring", function()
    local bufnr_before = vim.fn.bufnr("mdview://logs")
    log.append("second-marker")
    local ok, err = pcall(log.show)
    vim.wait(50)
    assert.is_true(ok, tostring(err))
    assert.are.equal(bufnr_before, vim.fn.bufnr("mdview://logs"))
  end)

  it("respects a custom buf_name override", function()
    with_clean_overrides(function()
      log.setup({ buf_name = "mdview://logs-custom" })
      log.show()
      vim.wait(50)
      assert(vim.fn.bufnr("mdview://logs-custom") ~= -1, "expected the custom-named buffer to exist")
    end)
  end)
end)

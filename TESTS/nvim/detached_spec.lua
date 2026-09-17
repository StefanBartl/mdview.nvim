---@module 'tests.nvim.detached_spec'
-- Verifies mdview.adapter.detached's two pure(ish) helpers: build_env (the
-- child-environment list libuv wants) and resolve_target (the file a
-- standalone preview should watch). M.spawn itself is not exercised here --
-- it's a real uv.spawn() of an arbitrary external command (see
-- TESTS/README.md); its cmd-validation guard is covered indirectly through
-- these two.

---@diagnostic disable: undefined-global

local detached = require("mdview.adapter.detached")

--- Find `key=value` in a libuv-style "KEY=VALUE" string list.
---@param env string[]
---@param key string
---@return string|nil
local function find_env(env, key)
  for _, kv in ipairs(env) do
    local k, v = kv:match("^([^=]+)=(.*)$")
    if k == key then
      return v
    end
  end
  return nil
end

describe("detached.build_env", function()
  it("returns nil for nil/empty extra (inherit as-is)", function()
    assert.is_nil(detached.build_env(nil))
    assert.is_nil(detached.build_env({}))
  end)

  it("layers extra vars on top of the inherited environment", function()
    local marker_key = "MDVIEW_SPEC_DETACHED_MARKER"
    vim.env[marker_key] = nil -- make sure it's genuinely new, not a leftover
    local env = detached.build_env({ [marker_key] = "hello" })
    assert.are.equal("hello", find_env(env, marker_key))
    -- Something that was already in this process's own environment is
    -- still present too (inherited, not replaced).
    assert(#env > 1, "expected more than just the one extra var")
  end)

  it("an extra var overrides an inherited one of the same name", function()
    local key = "MDVIEW_SPEC_DETACHED_OVERRIDE"
    vim.env[key] = "original"
    local env = detached.build_env({ [key] = "overridden" })
    assert.are.equal("overridden", find_env(env, key))
    vim.env[key] = nil
  end)
end)

describe("detached.resolve_target", function()
  it("resolves an explicit relative arg to an absolute, readable path", function()
    local tmp = vim.fn.tempname()
    local f = io.open(tmp, "w")
    f:write("content")
    f:close()

    local dir = vim.fn.fnamemodify(tmp, ":h")
    local base = vim.fn.fnamemodify(tmp, ":t")
    local cwd_before = vim.fn.getcwd()
    vim.cmd("cd " .. vim.fn.fnameescape(dir))
    local path, err = detached.resolve_target(base)
    vim.cmd("cd " .. vim.fn.fnameescape(cwd_before))

    assert.is_nil(err)
    assert.are.equal(vim.fs.normalize(tmp), path)
    vim.fn.delete(tmp)
  end)

  it("errors on a non-existent explicit path", function()
    local path, err = detached.resolve_target("/no/such/file-mdview-spec.md")
    assert.is_nil(path)
    assert(err and err:find("not a readable file", 1, true), tostring(err))
  end)

  it("falls back to the current buffer's file when no arg is given", function()
    local tmp = vim.fn.tempname() .. ".md"
    local f = io.open(tmp, "w")
    f:write("x")
    f:close()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, tmp)
    vim.api.nvim_set_current_buf(buf)

    local path, err = detached.resolve_target(nil)
    assert.is_nil(err)
    assert.are.equal(vim.fs.normalize(tmp), path)
    vim.fn.delete(tmp)
  end)

  it("errors when there is no arg and the current buffer has no file", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    local path, err = detached.resolve_target(nil)
    assert.is_nil(path)
    assert(err and err:find("current buffer has no file", 1, true), tostring(err))
  end)
end)

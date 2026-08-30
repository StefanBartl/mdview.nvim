---@module 'tests.nvim.server_args_spec'
-- Verifies mdview.adapter.server_args' notion of "a path uv.spawn() can start",
-- which is not the same as vim.fn.executable(). libuv resolves a command with
-- no extension by appending each PATHEXT entry and never tries the bare name,
-- so on Windows an extension-less relay binary passes executable() and then
-- spawns as ENOENT — the failure this guards against.

---@diagnostic disable: undefined-global

local server_args = require("mdview.adapter.server_args")

local windows = vim.fn.has("win32") == 1

--- Run `fn(dir)` with a fresh temp directory, removed again afterwards.
---@param fn fun(dir: string)
---@return nil
local function with_tempdir(fn)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local ok, err = pcall(fn, dir)
  vim.fn.delete(dir, "rf")
  if not ok then
    error(err, 0)
  end
end

--- Create an empty file and make it executable where that means anything.
---@param path string
---@return string path
local function touch_executable(path)
  -- Not assert(io.open(...)): the harness's assert() is a bare guard and
  -- returns nothing, so wrapping the handle in it throws the handle away.
  local f = io.open(path, "w")
  assert(f, "could not create " .. path)
  f:write("")
  f:close()
  if not windows then
    os.execute(("chmod +x %q"):format(path))
  end
  return path
end

describe("server_args.built_binary_name", function()
  it("carries .exe exactly on Windows", function()
    assert.are.equal(windows and "mdview-server.exe" or "mdview-server", server_args.built_binary_name())
  end)
end)

describe("server_args.spawnable", function()
  it("returns nil for a path that does not exist", function()
    with_tempdir(function(dir)
      assert.is_nil(server_args.spawnable(dir .. "/mdview-server"))
    end)
  end)

  it("finds the binary build:go writes on this platform", function()
    with_tempdir(function(dir)
      local base = dir .. "/mdview-server"
      local built = touch_executable(base .. (windows and ".exe" or ""))
      assert.are.equal(built, server_args.spawnable(base))
    end)
  end)

  it("on Windows, refuses an extension-less file and takes the .exe beside it", function()
    if not windows then
      -- Elsewhere the extension-less file *is* the binary — covered above.
      return
    end
    with_tempdir(function(dir)
      local base = touch_executable(dir .. "/mdview-server")
      assert.is_nil(server_args.spawnable(base))

      local exe = touch_executable(base .. ".exe")
      assert.are.equal(exe, server_args.spawnable(base))
    end)
  end)

  it("leaves a path that already carries an extension alone", function()
    with_tempdir(function(dir)
      local named = touch_executable(dir .. "/relay.bin")
      assert.are.equal(named, server_args.spawnable(named))
    end)
  end)
end)

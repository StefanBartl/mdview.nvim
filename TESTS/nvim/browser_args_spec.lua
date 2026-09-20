---@module 'tests.nvim.browser_args_spec'
-- Verifies mdview.adapter.browser.build_args_for_browser (per-family CLI args
-- for the isolated-mode browser launch) and the explicit_cmd/friendly-name
-- precedence in mdview.adapter.browser.resolve_command. Neither had any
-- coverage before. Autodetection/platform-probe branches are not exercised
-- here (see TESTS/README.md) -- they depend on what happens to be installed
-- and where on the machine actually running the suite.

---@diagnostic disable: undefined-global

local build_args = require("mdview.adapter.browser.build_args_for_browser")
local resolve_command = require("mdview.adapter.browser.resolve_command")
local bcfg = require("mdview.config.browser")

local windows = vim.fn.has("win32") == 1

--- Create an empty, executable (where that means anything) file.
---@param path string
---@return string path
local function touch_executable(path)
  local f = io.open(path, "w")
  assert(f, "could not create " .. path)
  f:write("")
  f:close()
  if not windows then
    os.execute(("chmod +x %q"):format(path))
  end
  return path
end

---@param fn fun(dir: string)
local function with_tempdir(fn)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local ok, err = pcall(fn, dir)
  vim.fn.delete(dir, "rf")
  if not ok then
    error(err, 0)
  end
end

describe("build_args_for_browser", function()
  it("builds Chrome/Chromium/Edge args with a persistent profile dir and the URL last", function()
    for _, exe in ipairs({
      "chrome",
      "chromium",
      "msedge",
      "microsoft-edge",
      "/usr/bin/microsoft-edge-stable",
      "google-chrome",
      "/usr/bin/Google-Chrome",
    }) do
      local args, tmp = build_args(exe, "http://localhost:1/?x=1")
      assert(tmp and tmp ~= "", "expected a profile dir for " .. exe)
      assert.are.equal("http://localhost:1/?x=1", args[#args])
      local has_profile = false
      for _, a in ipairs(args) do
        if a:match("^%-%-user%-data%-dir=") then
          has_profile = true
        end
      end
      assert.is_true(has_profile, "expected --user-data-dir= for " .. exe)
    end
  end)

  it("builds Firefox args with -profile and --no-remote", function()
    local args, tmp = build_args("firefox", "http://localhost:1/")
    assert.are.equal("-profile", args[1])
    assert.are.equal(tmp, args[2])
    local has_no_remote = false
    for _, a in ipairs(args) do
      if a == "--no-remote" then
        has_no_remote = true
      end
    end
    assert.is_true(has_no_remote)
    assert.are.equal("http://localhost:1/", args[#args])
  end)

  it("falls back to a generic --user-data-dir/--new-window form for anything else", function()
    local args = build_args("/opt/some-browser/bin", "http://localhost:1/")
    assert.are.equal("http://localhost:1/", args[#args])
    local has_new_window = false
    for _, a in ipairs(args) do
      if a == "--new-window" then
        has_new_window = true
      end
    end
    assert.is_true(has_new_window)
  end)

  it("matching is case-insensitive on the executable name", function()
    local args = build_args("C:\\Path\\To\\CHROME.EXE", "http://localhost:1/")
    local has_new_window = false
    for _, a in ipairs(args) do
      if a == "--new-window" then
        has_new_window = true
      end
    end
    assert.is_true(has_new_window)
  end)

  it("reuses the same profile dir across repeated calls", function()
    local _, tmp1 = build_args("chrome", "http://a/")
    local _, tmp2 = build_args("chrome", "http://b/")
    assert.are.equal(tmp1, tmp2)
  end)
end)

describe("resolve_command explicit_cmd / config precedence", function()
  it("returns an explicit absolute browser_cmd that resolves as executable", function()
    with_tempdir(function(dir)
      local exe = touch_executable(dir .. "/mybrowser" .. (windows and ".bat" or ""))
      local cmd, err = resolve_command(exe, nil)
      assert.are.equal(exe, cmd)
      assert.is_nil(err)
    end)
  end)

  it("errors out (does not fall through) when the explicit browser_cmd is not usable", function()
    with_tempdir(function(dir)
      local missing = dir .. "/does-not-exist"
      local cmd, err = resolve_command(missing, "firefox")
      assert.is_nil(cmd)
      assert(err and err:find("not usable", 1, true), "expected a 'not usable' error, got: " .. tostring(err))
    end)
  end)

  it("prefers config.browser.resolved_browser_cmd over autodetection", function()
    with_tempdir(function(dir)
      local exe = touch_executable(dir .. "/from-config" .. (windows and ".bat" or ""))
      local orig = bcfg.defaults.resolved_browser_cmd
      bcfg.defaults.resolved_browser_cmd = exe
      local cmd, err = resolve_command(nil, nil)
      bcfg.defaults.resolved_browser_cmd = orig
      assert.are.equal(exe, cmd)
      assert.is_nil(err)
    end)
  end)

  it("falls through to friendly-name/autodetect when the configured cmd is stale", function()
    with_tempdir(function(dir)
      local orig = bcfg.defaults.resolved_browser_cmd
      bcfg.defaults.resolved_browser_cmd = dir .. "/gone-missing"
      -- No explicit cmd, no friendly name that resolves, and (most likely)
      -- no real browser installed in this sandboxed CI environment either --
      -- either a real candidate is found on this machine, or resolution
      -- fails with the expected "no suitable browser" message. Both are
      -- "did not silently return the stale configured path".
      local cmd, err = resolve_command(nil, nil)
      bcfg.defaults.resolved_browser_cmd = orig
      if cmd then
        assert.is_false(cmd == dir .. "/gone-missing")
      else
        assert(err and err:find("no suitable browser", 1, true), tostring(err))
      end
    end)
  end)
end)

---@module 'plugin.mdview'
--- Lightweight plugin entrypoint for mdview.nvim.
--- Provides user commands to start/stop the preview server from Neovim.
--- Implements runtime + package manager check, version check, and healthcheck.

---@diagnostic disable: undefined-field, deprecated, unused-local

local M = {}

local uv = vim.loop
local api = vim.api
local notify = vim.notify
local mdview = require("mdview")

--AUDIT: Modulariesieren

-- Detect OS
local is_windows = uv.os_uname().version:match("Windows")

--- Execute command and return true if it succeeds
local function executable_exists(cmd)
  local ok, popen_handle = pcall(io.popen, cmd .. " --version")
  if ok and popen_handle then
    local _ = popen_handle:read("*a")
    popen_handle:close()
    return true
  end
  return false
end

--- Detect JS runtime (Node or Bun) and major version
local function detect_runtime()
  local candidates = { "node", "bun" }
  for _, cmd in ipairs(candidates) do
    if is_windows and cmd == "npm" then
      cmd = "npm.cmd"
    end
    if executable_exists(cmd) then
      local handle, version = io.popen(cmd .. " --version")
			if handle then
			local output = handle:read("*a")
				handle:close()
				local major = tonumber(output:match("v?(%d+)"))
				return cmd, major
			else
        vim.notify("[mdview] handle to read output in runtime detection is nil", 4)
			end
    end
  end
  return nil, nil
end

local runtime, major_version = detect_runtime()
if not runtime then
  vim.schedule(function()
    notify(
      "mdview.nvim: no compatible JS runtime found (requires Node>=18 or Bun>=0.8). Plugin disabled.",
      vim.log.levels.ERROR,
      {}
    )
  end)
  return M
end

-- Check runtime version
local min_version = (runtime:match("node")) and 18 or 0.8
if major_version and major_version < min_version then
  vim.schedule(function()
    notify(
      string.format(
        "mdview.nvim: detected %s version %s, but minimum required is %s. Plugin disabled.",
        runtime, tostring(major_version), tostring(min_version)
      ),
      vim.log.levels.ERROR,
      {}
    )
  end)
  return M
end

-- Check that package manager is available (npm or bun)
local pkg_cmd = (runtime:match("node")) and "npm" or "bun"
if is_windows and pkg_cmd == "npm" then
  pkg_cmd = "npm.cmd"
end
if not executable_exists(pkg_cmd) then
  vim.schedule(function()
    notify(
      string.format("mdview.nvim: package manager '%s' not found. Plugin disabled.", pkg_cmd),
      vim.log.levels.ERROR,
      {}
    )
  end)
  return M
end

return M

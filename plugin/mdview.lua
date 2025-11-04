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

-- Register User Commands
vim.api.nvim_create_user_command("MDViewStart", function()
  mdview.start()
end, { desc = "Start mdview preview server and attach autocommands" })

vim.api.nvim_create_user_command("MDViewStop", function()
  mdview.stop()
end, { desc = "Stop mdview preview server and detach autocommands" })


-- Replace the project root detection / dev-fallback with a REPOS_DIR-aware version.
-- This snippet prefers an explicit REPOS_DIR environment variable (vim.env.REPOS_DIR)
-- and falls back to git-root or cwd. It verifies existence with vim.loop.fs_stat
-- before attempting to dofile() the health.lua file.
--

-- Helper: join path parts with "/" (forward slashes work on Windows and POSIX in Neovim)
local function path_join(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = select(i, ...)
  end
  return table.concat(parts, "/")
end

-- Helper: check if file exists
local function file_exists(path)
  return vim.loop.fs_stat(path) ~= nil
end

-- Detect project root using (in order):
-- 1. REPOS_DIR environment variable (common in dev setups)
-- 2. git top-level (if available)
-- 3. current working directory
local function detect_project_root()
  -- 1) prefer explicit REPOS_DIR if set
  local repos_dir = vim.env.REPOS_DIR
  if repos_dir and repos_dir ~= "" then
    -- try common repository folder names under REPOS_DIR
    local candidates = {
      path_join(repos_dir, "mdview.nvim"),
      path_join(repos_dir, "mdview"),
    }
    for _, cand in ipairs(candidates) do
      -- check for lua/mdview/health.lua inside candidate repo
      local health_path = path_join(cand, "lua", "mdview", "health.lua")
      if file_exists(health_path) then
        return cand
      end
    end
    -- if REPOS_DIR set but no mdview repo found, still fallthrough to other checks
  end

  -- 2) try git root
  local ok, handle = pcall(io.popen, "git rev-parse --show-toplevel 2>nul")
  if ok and handle then
    local out = handle:read("*a")
    handle:close()
    out = out and out:gsub("%s+$", "") or ""
    if out ~= "" and file_exists(path_join(out, "lua", "mdview", "health.lua")) then
      return out
    end
  end

  -- 3) fallback to current working directory if it contains the file
  local cwd = vim.fn.getcwd()
  if file_exists(path_join(cwd, "lua", "mdview", "health.lua")) then
    return cwd
  end

  -- nothing found
  return nil
end

-- Use the detected root to attempt dev fallback
local root = detect_project_root()
if not root then
  vim.schedule(function()
    notify(
      "mdview.nvim: dev health.lua not found (checked REPOS_DIR, git root, cwd).",
      vim.log.levels.WARN,
      {}
    )
  end)
  return
end

local health_path = path_join(root, "lua", "mdview", "health.lua")
-- safety: double-check existence before loading
if not file_exists(health_path) then
  vim.schedule(function()
    notify("mdview.nvim: dev health.lua not found at: " .. tostring(health_path), vim.log.levels.WARN, {})
  end)
  return
end

local ok_dofile, err = pcall(dofile, health_path)
if not ok_dofile then
  vim.schedule(function()
    notify("mdview.nvim: health module dev fallback failed: " .. tostring(err), vim.log.levels.WARN, {})
  end)
  return
end



return M

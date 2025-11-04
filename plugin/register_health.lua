---@module 'plugin.mdview.register_health'
--- Register the mdview health provider safely.
--- This module is intended to live in the plugin/ directory and be invoked
--- from plugin/mdview.lua during startup. It will attempt to require the
--- runtime health module (lua/mdview/health.lua) and register its
--- health_report function with Neovim's health API. If the module cannot be
--- required and the plugin is running in development mode (mdview.config.defaults.dev_local),
--- it will attempt a dev fallback using REPOS_DIR / git root / cwd to locate
--- the workspace and load health.lua via dofile().
---
--- The module will not error if health#register is not yet available; instead
--- it defers registration to VimEnter.

local M = {}

local notify = vim.notify
local schedule = vim.schedule

-- Helper: join path parts with "/" (normalized)
local function path_join(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = select(i, ...)
  end
  return table.concat(parts, "/")
end

-- Helper: check if file exists using luv fs_stat
local function file_exists(path)
	---@diagnostic disable-next-line FIX:
  return vim.loop.fs_stat(path) ~= nil
end

-- Detect project root using (in order): REPOS_DIR, git top-level, cwd
local function detect_project_root()
  -- 1) prefer explicit REPOS_DIR if set
  local repos_dir = vim.env.REPOS_DIR
  if repos_dir and repos_dir ~= "" then
    local candidates = {
      path_join(repos_dir, "mdview.nvim"),
      path_join(repos_dir, "mdview"),
    }
    for _, cand in ipairs(candidates) do
      local health_path = path_join(cand, "lua", "mdview", "health.lua")
      if file_exists(health_path) then
        return cand
      end
    end
    -- fallthrough if not found under REPOS_DIR
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

-- Attempt to register the health_report function with Neovim's health API.
-- If health#register is not available yet, defer to VimEnter.
local function register_health_report(mod)
  if not mod or type(mod.health_report) ~= "function" then
    return false, "module has no health_report function"
  end

  local function do_register()
    if vim.fn.exists("*health#register") == 1 then
      local ok, err = pcall(vim.fn["health#register"], "mdview", mod.health_report)
      if not ok then
        return false, tostring(err)
      end
      return true
    end
    return false, "health#register not available"
  end

  local ok, _ = do_register()
  if ok then
    return true
  end

  -- defer registration to VimEnter once; if still not available, give up silently
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      if vim.fn.exists("*health#register") == 1 then
        pcall(vim.fn["health#register"], "mdview", mod.health_report)
      end
    end,
  })

  return true
end

--- Setup / init function for health registration.
--- Tries require('mdview.health') first. If that fails and dev_local is enabled
--- in mdview.config.defaults, attempts a dev fallback using REPOS_DIR/git-root/cwd.
---@return boolean ok, string|nil err
function M.setup()
  -- try require() first (normal installed plugin case)
  local ok, mod_or_err = pcall(require, "mdview.health")
  if ok and type(mod_or_err) == "table" and type(mod_or_err.health_report) == "function" then
    local reg_ok, reg_err = register_health_report(mod_or_err)
    if not reg_ok then
      return false, reg_err
    end
    return true
  end

  -- require failed; consult config.dev_local to decide whether to attempt dev fallback
  local cfg_ok, cfg = pcall(require, "mdview.config")
  local dev_local = false
  if cfg_ok and cfg and cfg.defaults and cfg.defaults.dev_local ~= nil then
    dev_local = cfg.defaults.dev_local
  end

  if not dev_local then
    -- intentionally silent for normal installs; warn for clarity in dev setups
    schedule(function()
      notify("mdview.nvim: health module not found; dev_local disabled — skipping dev fallback", vim.log.levels.WARN, {})
    end)
    return false, "dev_local disabled and require failed"
  end

  -- dev fallback: detect project root and try to dofile health.lua
  local root = detect_project_root()
  if not root then
    schedule(function()
      notify("mdview.nvim: dev health.lua not found (checked REPOS_DIR, git root, cwd).", vim.log.levels.WARN, {})
    end)
    return false, "dev health.lua not found"
  end

  local health_path = path_join(root, "lua", "mdview", "health.lua")
  if not file_exists(health_path) then
    schedule(function()
      notify("mdview.nvim: dev health.lua not found at: " .. tostring(health_path), vim.log.levels.WARN, {})
    end)
    return false, "health.lua absent at detected root"
  end

  local ok_dofile, mod = pcall(dofile, health_path)
  if not ok_dofile then
    schedule(function()
      notify("mdview.nvim: health module dev fallback failed: " .. tostring(mod), vim.log.levels.WARN, {})
    end)
    return false, tostring(mod)
  end

  if type(mod) ~= "table" or type(mod.health_report) ~= "function" then
    schedule(function()
      notify("mdview.nvim: dev health module loaded but missing health_report()", vim.log.levels.WARN, {})
    end)
    return false, "invalid dev health module"
  end

  -- register (or defer) the health_report from dev module
  register_health_report(mod)
  return true
end

return M

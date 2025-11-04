---@module 'mdview.health'
--- Healthcheck module for mdview.nvim
--- Exports two helpers:
---  - `health_report(report)` : internal helper compatible with older health#register style
---  - `check()`              : function expected by :checkhealth (calls vim.health.*)

local M = {}

local uv = vim.loop
local schedule = vim.schedule

-- Helper: check if executable exists by probing `--version`
-- Comments in English per project code style.
local function executable_exists(cmd)
  local ok, handle = pcall(io.popen, cmd .. " --version 2>nul")
  if not ok or not handle then
    return false
  end
  local _ = handle:read("*a")
  pcall(handle.close, handle)
  return true
end

-- Detect runtime and major version (node or bun)
local function detect_runtime()
  local is_windows = uv.os_uname and tostring(uv.os_uname().version):match("Windows")
  local candidates = { "node", "bun" }
  for _, c in ipairs(candidates) do
    local probe = c
    if is_windows and probe == "npm" then
      probe = "npm.cmd"
    end
    if executable_exists(probe) then
      local ok, handle = pcall(io.popen, probe .. " --version 2>nul")
      if ok and handle then
        local out = handle:read("*a")
        pcall(handle.close, handle)
        local major = tonumber(out:match("v?(%d+)"))
        return probe, major or nil
      end
      return probe, nil
    end
  end
  return nil, nil
end

-- Internal helper used by plugin.register path (report object style)
-- Accepts `report` object that responds to :ok(), :error(), :warn() (health#register)
function M.health_report(report)
  local runtime, major = detect_runtime()
  if runtime then
    report.ok("JS runtime detected: " .. runtime .. " (version " .. tostring(major) .. ")")
  else
    report.error("No compatible JS runtime found (Node>=18 or Bun>=0.8 required)")
  end

  local pkg_cmd = (runtime and runtime:match("node")) and "npm" or "bun"
  if uv.os_uname and tostring(uv.os_uname().version):match("Windows") and pkg_cmd == "npm" then
    pkg_cmd = "npm.cmd"
  end

  if executable_exists(pkg_cmd) then
    report.ok("Package manager available: " .. pkg_cmd)
  else
    report.warn("Package manager '" .. pkg_cmd .. "' not found")
  end
end

-- check() function expected by :checkhealth
-- Uses the vim.health.* API to produce a structured report.
function M.check()
  -- Ensure vim.health API exists
  if not vim.health then
    -- Fallback: notify user if health API missing (very unlikely)
    schedule(function()
      vim.notify("mdview.nvim: vim.health API not available; cannot run :checkhealth", vim.log.levels.WARN, {})
    end)
    return
  end

  vim.health.start("mdview: environment check")

  local runtime, major = detect_runtime()
  if runtime then
    if major then
      vim.health.ok("JS runtime detected: " .. runtime .. " (version " .. tostring(major) .. ")")
    else
      vim.health.ok("JS runtime detected: " .. runtime .. " (version unknown)")
    end
  else
    vim.health.error("No compatible JS runtime found (Node>=18 or Bun>=0.8 required)")
  end

  local pkg_cmd = (runtime and runtime:match("node")) and "npm" or "bun"
  if uv.os_uname and tostring(uv.os_uname().version):match("Windows") and pkg_cmd == "npm" then
    pkg_cmd = "npm.cmd"
  end

  if executable_exists(pkg_cmd) then
    vim.health.ok("Package manager available: " .. pkg_cmd)
  else
    vim.health.error("Package manager '" .. pkg_cmd .. "' not found")
  end

  -- Additional optional checks: package.json presence when running from editor
  local function file_exists(path)
    return uv.fs_stat(path) ~= nil
  end

  -- Attempt to detect project root similarly to dev fallback logic
  local function detect_project_root()
    local repos_dir = vim.env.REPOS_DIR
    if repos_dir and repos_dir ~= "" then
      local cand = repos_dir .. "/mdview.nvim"
      if file_exists(cand .. "/package.json") or file_exists(cand .. "/lua/mdview/health.lua") then
        return cand
      end
      cand = repos_dir .. "/mdview"
      if file_exists(cand .. "/package.json") or file_exists(cand .. "/lua/mdview/health.lua") then
        return cand
      end
    end

    local ok, handle = pcall(io.popen, "git rev-parse --show-toplevel 2>nul")
    if ok and handle then
      local out = handle:read("*a")
      pcall(handle.close, handle)
      out = out and out:gsub("%s+$", "") or ""
      if out ~= "" and file_exists(out .. "/package.json") then
        return out
      end
    end

    local cwd = vim.fn.getcwd()
    if file_exists(cwd .. "/package.json") then
      return cwd
    end
    return nil
  end

  local root = detect_project_root()
  if root then
    vim.health.ok("Found project root for mdview at: " .. tostring(root))
    if file_exists(root .. "/package.json") then
      vim.health.ok("package.json present in project root")
    else
      vim.health.warn("No package.json found in detected project root; MDViewStart using npm scripts will fail")
    end
  else
    vim.health.warn("Project root not detected automatically (set REPOS_DIR or open a file inside the project)")
  end
end

return M

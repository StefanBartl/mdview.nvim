---@module 'mdview.health'
--- CheckHealth module for mdview.nvim
--- Integrates with :checkhealth and provides runtime/package-manager diagnostics.

--AUDIT: Diese Datei muss währen der Development Phase laufend erweitert/angepasst werden

---@diagnostic disable: undefined-field, deprecated, unused-local

local uv = vim.loop
local M = {}

-- Detect OS
local is_windows = uv.os_uname().version:match("Windows")

-- Helper: check if executable exists
local function executable_exists(cmd)
  local ok, popen_handle = pcall(io.popen, cmd .. " --version")
  if ok and popen_handle then
    local _ = popen_handle:read("*a")
    popen_handle:close()
    return true
  end
  return false
end

-- Detect runtime and major version
local function detect_runtime()
  local candidates = { "node", "bun" }
  for _, cmd in ipairs(candidates) do
    if is_windows and cmd == "npm" then
      cmd = "npm.cmd"
    end
    if executable_exists(cmd) then
      local handle = io.popen(cmd .. " --version")
      if handle then
				local output = handle:read("*a")
				handle:close()
				local major = tonumber(output:match("v?(%d+)"))
				return cmd, major
			else
        vim.notify("[mdview] handle to read output in health module is nil", 4)
			end
    end
  end
  return nil, nil
end

-- Healthcheck function called by :checkhealth
---@param report table health report API
local function health_report(report)
  local runtime, major_version = detect_runtime()
  if runtime then
    report.ok("JS runtime detected: " .. runtime .. " (version " .. tostring(major_version) .. ")")
  else
    report.error("No compatible JS runtime found (Node>=18 or Bun>=0.8 required)")
  end

  local pkg_cmd = (runtime and runtime:match("node")) and "npm" or "bun"
  if is_windows and pkg_cmd == "npm" then
    pkg_cmd = "npm.cmd"
  end
  if executable_exists(pkg_cmd) then
    report.ok("Package manager available: " .. pkg_cmd)
  else
    report.error("Package manager '" .. pkg_cmd .. "' not found")
  end
end

-- Export the health_report function and module table.
-- The plugin is responsible for calling health#register when the health API is available.
M.health_report = health_report

return M

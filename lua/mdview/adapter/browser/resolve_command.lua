---@module 'mdview.adapter.browser.resolve_command'
--- Resolve a browser executable by explicit command, configuration, friendly name, autodetection, and platform-specific probes.

---@class browser_resolver
---@field try_resolve fun(string): boolean function to test if a candidate command is valid
---@field default_candidates string[] list of fallback browser executable names
---@field browser_cfg table plugin/browser configuration with get_resolved_cmd method
---@field probe_platform_paths fun(): string[] returns platform-specific candidate paths

local fn = vim.fn
local browser_cfg = require("mdview.config.browser")
local probe_platform_paths = require("mdview.adapter.browser.probe_plattform_paths")

-- Default candidate names
---@type string[]
local default_candidates = { "chrome", "google-chrome", "chromium", "msedge", "firefox" }

-- Test whether a candidate path/name is usable
---@param name string
---@return string|nil resolved -- returns the input or absolute candidate path or nil
local function try_resolve(name)
  if not name or name == "" then return nil end
  -- If it's directly executable in PATH
  if fn.executable(name) == 1 then
    return name
  end
  -- If it's an absolute path to an executable-like file, accept it (filereadable fallback)
  if fn.filereadable(name) == 1 then
    return name
  end
  return nil
end

---@param explicit_cmd string|nil Explicit browser command (highest precedence)
---@param friendly string|nil Optional friendly name for browser (e.g., "firefox", "chrome")
---@return string|nil resolved_cmd Resolved browser command
---@return string|nil err Error message if resolution failed
local function resolve_command(explicit_cmd, friendly)
  -- Highest precedence: explicit absolute command
  if explicit_cmd and explicit_cmd ~= "" then
    if try_resolve(explicit_cmd) then
      return explicit_cmd, nil
    else
      return nil, ("explicit browser_cmd not usable: %s"):format(tostring(explicit_cmd))
    end
  end

  -- Attempt resolved configuration command from plugin/browser config
  local cfg_cmd = browser_cfg.get_resolved_cmd()
  if cfg_cmd and cfg_cmd ~= "" then
    if try_resolve(cfg_cmd) then
      return cfg_cmd, nil
    end
    -- fallthrough if invalid
  end

  -- Try friendly name first (best-effort)
  if friendly and friendly ~= "" then
    local r = try_resolve(friendly) or nil
    if r then return r, nil end
  end

  -- Autodetect: flatten friendly + default candidates into a single list
  local candidates = vim.iter({ friendly and { friendly } or {}, default_candidates })
    :flatten()    -- flatten one level; safe: dict-like tables cause error
    :totable()

  for _, cand in ipairs(candidates) do
    local r = try_resolve(cand)
    if r then
      return r, nil
    end
  end

  -- Platform-specific probes as last resort
  for _, p in ipairs(probe_platform_paths()) do
    if try_resolve(p) then
      return p, nil
    end
  end

  return nil, "no suitable browser executable found on PATH or common locations"
end

return {
  resolve_command = resolve_command,
}

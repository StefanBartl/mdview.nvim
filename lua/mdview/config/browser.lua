---@module 'mdview.config.browser'
-- Browser detection and explicit user overrides for mdview.
-- This helper provides:
--  - config defaults for browser detection
--  - a validation/resolve step during setup
--  - a small public API to get the resolved browser command
--  - clear user-facing notifications on failure

local fn = vim.fn
local executable = fn.executable
local filereadable = fn. filereadable
local notify = vim.notify

local M = {}

-- default config fields; plugin should merge user overrides into this table
---@type table
M.defaults = {
  autodetect_browser = true,    -- try to locate a browser automatically
  browser = "",                 -- friendly name e.g. "chrome" or "firefox"
  browser_cmd = "",             -- absolute path to executable to force use
  stop_closes_browser = true,   -- :MDViewStop closes controlled browser by default
  autostart_open_browser = false, -- open browser automatically on start
  -- internal resolved value (populated during setup())
  _resolved_browser_cmd = nil,
}

-- Known candidate names to probe in PATH and platform locations (order matters)
---@type string[]
M._candidates = { "chrome", "google-chrome", "chromium", "msedge", "firefox" }

-- Validate that a path is an executable that can be launched.
-- Uses vim.executable() where appropriate; falls back to filereadable for platform bundle paths.
---@param path string
---@return boolean
local function is_executable(path)
  if not path or path == "" then return false end
  -- On windows/mac paths might be absolute; try vim's executable() first
  if executable(path) == 1 then return true end
  -- fallback: check readable file (some mac app bundle paths are not "executable" from PATH)
  if filereadable(path) == 1 then return true end
  return false
end

-- Try to resolve candidate name via PATH and common platform locations.
-- Returns absolute command string or nil.
---@param name string
---@return string|nil
local function resolve_candidate(name)
  if not name or name == "" then return nil end
  if executable(name) == 1 then
    return name
  end

	-- windows extra checks
  if fn.has("win32") == 1 then
    local program_files = { os.getenv("PROGRAMFILES"), os.getenv("PROGRAMFILES(X86)"), os.getenv("LOCALAPPDATA") }
    for _, base in ipairs(program_files) do
      if base and base ~= vim.NIL then
        local candidates = {
          base .. "\\Google\\Chrome\\Application\\chrome.exe",
          base .. "\\Chromium\\Application\\chrome.exe",
          base .. "\\Microsoft\\Edge\\Application\\msedge.exe",
        }
        for _, p in ipairs(candidates) do
          if filereadable(p) == 1 then return p end
        end
      end
    end
  end

	-- macOS app bundles common locations
  if fn.has("mac") == 1 then
    local mac_candidates = {
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
      "/Applications/Firefox.app/Contents/MacOS/firefox",
    }
    for _, p in ipairs(mac_candidates) do
      if filereadable(p) == 1 or executable(p) == 1 then
        return p
      end
    end
  end

	-- unix common names (common bin locations)
  local unix_candidates = {
    "/usr/bin/google-chrome",
    "/usr/bin/chromium-browser",
    "/usr/bin/chromium",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/msedge",
    "/usr/bin/firefox",
  }
  for _, p in ipairs(unix_candidates) do
    if filereadable(p) == 1 or executable(p) == 1 then return p end
  end
  return nil
end

-- Resolve browser command according to config precedence:
--  1. browser_cmd explicit override (absolute path) -> must be executable
--  2. browser friendly name -> resolve_candidate
--  3. autodetect via _candidates list
-- The resolved command is stored in M.defaults._resolved_browser_cmd
---@return string|nil err
function M.resolve_and_validate()
  -- explicit absolute command override
  if M.defaults.browser_cmd and M.defaults.browser_cmd ~= "" then
    if is_executable(M.defaults.browser_cmd) then
      M.defaults._resolved_browser_cmd = M.defaults.browser_cmd
      return nil
    else
      return ("configured browser_cmd is not executable: %s"):format(tostring(M.defaults.browser_cmd))
    end
  end

  -- friendly name provided
  if M.defaults.browser and M.defaults.browser ~= "" then
    local r = resolve_candidate(M.defaults.browser)
    if r then
      M.defaults._resolved_browser_cmd = r
      return nil
    else
      return ("configured browser '%s' could not be resolved on this system"):format(M.defaults.browser)
    end
  end

  -- autodetect if allowed
  if M.defaults.autodetect_browser then
    for _, cand in ipairs(M._candidates) do
      local r = resolve_candidate(cand)
      if r then
        M.defaults._resolved_browser_cmd = r
        return nil
      end
    end
    -- no candidate found, but do not treat as fatal: return informative message
    return "auto-detection failed: no known browser executable found in PATH or common locations"
  end

  -- nothing to do
  return "no browser configured and autodetect disabled"
end

--- Public accessor for resolved browser command (nil if none)
---@return string|nil
function M.get_resolved_cmd()
  return M.defaults._resolved_browser_cmd
end

--- Convenience: call at plugin setup to attempt resolution and optionally notify user.
--- If notify_on_fail is true, a user-facing notification will be shown on errors/warnings.
---@param notify_on_fail boolean|nil
---@return boolean success, string|nil msg
function M.setup_and_notify(notify_on_fail)
  notify_on_fail = notify_on_fail == nil and true or notify_on_fail
  local err = M.resolve_and_validate()
  if err then
    if notify_on_fail then
      notify(("[mdview.config.browser] browser resolution: %s"):format(tostring(err)), vim.log.levels.WARN, {})
      notify("Hint: set mdview.config.browser_cmd to an absolute executable path to force use.", vim.log.levels.INFO, {})
    end
    return false, err
  end
  return true, nil
end

return M

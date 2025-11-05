---@module 'mdview.adapter.browser.build_args_for_browser'
-- Builds a command-line argument list for launching a given browser executable with a specified URL.
-- Supports Chrome/Chromium/Edge, Firefox, and fallback generic handling.

local fn = vim.fn

-- Create a temporary directory for browser profile; returns path string
---@return string tmpdir
local function make_tmp_profile()
  local base = fn.tempname()
  -- ensure directory exists (mkdir 'p')
  pcall(fn.mkdir, base, "p")
  return base
end

---@param exe string # Absolute path or candidate name of the browser executable
---@param url string # URL to open
---@return string[] args # Command-line arguments to pass to the executable
---@return string|nil tmp_profile # Path to temporary profile/directory (if created)
return function (exe, url)
  local name = exe:lower()
  local tmp = make_tmp_profile()

  if name:match("chrome") or name:match("chromium") or name:match("msedge") or name:match("google%-chrome") then
    local args = {
      "--user-data-dir=" .. tmp,
      "--app=" .. url,
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-extensions",
      "--disable-popup-blocking",
    }
    return args, tmp

  elseif name:match("firefox") then
    local args = {
      "-profile", tmp,
      "--new-instance",
      "--no-remote",
      url,
    }
    return args, tmp

  else
    -- generic fallback for other executables
    local args = {
      "--user-data-dir=" .. tmp,
      "--app=" .. url,
    }
    return args, tmp
  end
end

---@module 'mdview.adapter.browser.build_args_for_browser'
-- Builds a command-line argument list for launching a given browser executable with a specified URL.
-- Supports Chrome/Chromium/Edge, Firefox, and fallback generic handling.

local fn = vim.fn

-- A dedicated, persistent profile directory reused across invocations
-- (instead of a fresh fn.tempname() every time), so repeated :MDViewStart /
-- :MDViewOpen calls reuse the same mdview browser session/window rather than
-- piling up a new orphaned browser process each time (the roadmap's "reuse
-- the current browser session" request). Being a SEPARATE profile from the
-- user's everyday one is also what makes closing the preview window actually
-- terminate a distinct browser process — which is what
-- browser.stop_on_browser_exit / browser_autoclose rely on (launching into
-- the user's already-running browser would hand off to that process and
-- exit immediately, so close/exit could never be detected).
---@return string profile_dir
local function make_tmp_profile()
  local base = fn.stdpath("data") .. "/mdview/browser-profile"
  pcall(fn.mkdir, base, "p")
  return base
end

---@param exe string # Absolute path or candidate name of the browser executable
---@param url URL # URL to open
---@return string[] args # Command-line arguments to pass to the executable
---@return string|nil tmp_profile # Path to temporary profile/directory (if created)
return function (exe, url)
  local name = exe:lower()
  local tmp = make_tmp_profile()

  if name:match("chrome") or name:match("chromium") or name:match("msedge") or name:match("google%-chrome") then
    -- A normal browser window (taskbar icon, address bar) rather than a
    -- chromeless --app window: --app was dropped because it produced a
    -- window with no taskbar entry and no toolbar, which reads as broken.
    local args = {
      "--user-data-dir=" .. tmp,
      "--new-window",
      "--no-first-run",
      "--no-default-browser-check",
      url,
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
      "--new-window",
      url,
    }
    return args, tmp
  end
end

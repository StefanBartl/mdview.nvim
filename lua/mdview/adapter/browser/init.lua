---@module 'mdview.adapter.browser'
-- Cross-platform helper to open the preview browser and (in isolated mode)
-- close it later from Neovim. Two open modes (see mdview.config.browser.open_mode):
--
--   "default"  — open the URL in the user's normal default browser as a new
--                tab (their extensions/theme/profile apply). Uses the OS
--                opener (vim.ui.open / start / open / xdg-open). Returns a
--                handle with no job_id: mdview can't programmatically close
--                it, so browser_autoclose / stop_on_browser_exit are no-ops
--                in this mode. This is the markdown-preview.nvim-style
--                approach (see docs/Roadmap/markdown_preview/browser/tab.md).
--
--   "isolated" — spawn a dedicated browser process against a persistent
--                mdview-only profile (see build_args_for_browser). A separate
--                process, so closing it is detectable (on_exit) and
--                jobstop-able — which is what makes browser_autoclose /
--                stop_on_browser_exit work. No access to the user's
--                extensions/bookmarks.

-- Usage:
-- local browser = require('mdview.adapter.browser')
-- local handle, err = browser.open(url, { open_mode = "default", on_exit = fn })
-- if handle then ... store handle ... end
-- browser.close(handle)

local fn = vim.fn
local resolve_command = require("mdview.adapter.browser.resolve_command")
local build_args_for_browser = require("mdview.adapter.browser.build_args_for_browser")

local M = {}

-- Open `url` in the user's default browser via the OS opener, as a new tab.
-- Returns a handle with no job_id (nothing to close/track).
---@param url URL
---@return BrowserHandle|nil, string|nil
local function open_default(url)
  -- IMPORTANT: do NOT use vim.ui.open on Windows. It runs
  -- `cmd.exe /c start "" <url>`, and cmd.exe treats every `&` in the URL as
  -- a command separator — so our `?key=…&token=…&theme=…` URL is chopped at
  -- the first `&`, the browser opens WITHOUT the token, and the client
  -- refuses to connect (page stuck on "mdview loading…" forever). rundll32's
  -- FileProtocolHandler takes the URL as a single, non-shell-interpreted
  -- argument, so `&` is preserved (verified: the full query string arrives).
  local cmd
  if fn.has("win32") == 1 then
    cmd = { "rundll32.exe", "url.dll,FileProtocolHandler", url }
  elseif fn.has("mac") == 1 then
    cmd = { "open", url }
  else
    cmd = { "xdg-open", url }
  end

  local jid = fn.jobstart(cmd, { detach = true })
  if not jid or jid <= 0 then
    return nil, "failed to launch OS browser opener"
  end

  return { open_mode = "default" }, nil
end

-- Open `url` by spawning a dedicated, trackable browser process against the
-- isolated mdview profile. Returns a handle with a job_id for close().
---@param url URL
---@param opts BrowserOptions
---@return BrowserHandle|nil, string|nil
local function open_isolated(url, opts)
  local cmd, err = resolve_command(opts.browser_cmd, opts.browser)
  if not cmd then
    return nil, err
  end

  local args, tmp = build_args_for_browser(cmd, url)
  if not args then
    return nil, "failed to construct browser args"
  end

  local cmd_list = { cmd }
  for _, a in ipairs(args) do table.insert(cmd_list, a) end

  -- jobstart opts: keep detach=false so jobstop can be used later
  local jid
  jid = fn.jobstart(cmd_list, {
    detach = false,
    on_exit = function(_, code, _)
      if opts.on_exit and type(opts.on_exit) == "function" then
        pcall(opts.on_exit, jid, code)
      end
    end,
  })

  if not jid or jid <= 0 then
    return nil, ("failed to start browser process (jobstart returned %s)"):format(tostring(jid))
  end

  return {
    job_id = jid,
    tmp_profile = tmp,
    cmd = cmd,
    args = args,
    platform = (fn.has("win32") == 1 and "win") or (fn.has("mac") == 1 and "mac") or "unix",
  }, nil
end

-- Open a browser tab/window pointing to `url`.
-- Returns a BrowserHandle on success, nil and error string on failure.
---@param url URL
---@param opts BrowserOptions|nil # { open_mode?, browser_cmd?, browser?, on_exit? }
---@return BrowserHandle|nil, string|nil
function M.open(url, opts)
  opts = opts or {}
  if not url or url == "" then
    return nil, "empty url"
  end

  if opts.open_mode == "isolated" then
    return open_isolated(url, opts)
  end
  return open_default(url)
end

-- Close a previously opened browser handle via jobstop(). The profile
-- directory is intentionally left alone (see module docstring) — it's
-- reused by the next :MDViewStart / :MDViewOpen, not deleted.
-- If there is no job handle (external opener used), this is a no-op.
---@param handle BrowserHandle|nil
---@return boolean, string|nil
function M.close(handle)
  if not handle then return true, nil end
  if type(handle) ~= "table" then return false, "invalid handle" end

  local ok, err = pcall(function()
    if handle.job_id and handle.job_id > 0 then
      pcall(fn.jobstop, handle.job_id)
    end
  end)

  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

return M

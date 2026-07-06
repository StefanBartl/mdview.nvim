---@module 'mdview.adapter.browser'
-- Cross-platform helper to open a browser instance (app mode, isolated from
-- the user's real default browser profile) and close it later from Neovim.
-- Minimal, validated implementation that respects explicit user overrides from
-- mdview.config.browser when available. Falls back to best-effort detection.
--
-- The profile directory (see build_args_for_browser.make_tmp_profile) is
-- persistent, not a one-off temp dir — it's intentionally reused across
-- :MDViewStart / :MDViewOpen invocations so mdview reuses its own dedicated
-- browser session/window instead of spawning a fresh isolated instance every
-- time. Nothing here deletes it; treat it like a normal browser profile
-- directory.

-- Usage:
-- local browser = require('mdview.adapter.browser')
-- local handle, err = browser.open(url, { browser_cmd = "/full/path/to/chrome", browser = "chrome" })
-- if handle then ... store handle ... end
-- browser.close(handle)

local fn = vim.fn
local resolve_command = require("mdview.adapter.browser.resolve_command")
local build_args_for_browser = require("mdview.adapter.browser.build_args_for_browser")

local M = {}

-- Open a browser window/tab pointing to `url`.
-- Returns a BrowserHandle on success, nil and error string on failure.
---@param url URL
---@param opts BrowserOptions|nil
---@return BrowserHandle|nil, string|nil
function M.open(url, opts)
  opts = opts or {}
  if not url or url == "" then
    return nil, "empty url"
  end

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

  local handle = {
    job_id = jid,
    tmp_profile = tmp,
    cmd = cmd,
    args = args,
    platform = (fn.has("win32") == 1 and "win") or (fn.has("mac") == 1 and "mac") or "unix",
  }

  return handle, nil
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

---@module 'mdview.adapter.browser'
--- Cross-platform helper to open a disposable browser instance (app mode / isolated profile)
--- and close it later from Neovim.
--- Minimal, validated implementation that respects explicit user overrides from
--- mdview.config.browser when available. Falls back to best-effort detection.
---
--- Usage:
--- local browser = require('mdview.adapter.browser')
--- local handle, err = browser.open(url, { browser_cmd = "/full/path/to/chrome", browser = "chrome" })
--- if handle then ... store handle ... end
--- browser.close(handle)

local fn = vim.fn
local resolve_command = require("mdview.adapter.browser.resolve_command")
local build_args_for_browser = require("mdview.adapter.browser.build_args_for_browser")

---@class BrowserHandle
---@field job_id number jobstart id
---@field tmp_profile string|nil temporary profile path
---@field cmd string the executable launched
---@field args string[] the args used to start the process
---@field platform "win"|"mac"|"unix"

local M = {}

-- Remove temporary profile directory (recursively)
---@param path string|nil
local function remove_tmp_profile(path)
  if not path or path == "" then return end
  pcall(fn.delete, path, "rf")
end

--- Open a browser window/tab pointing to `url`.
--- Returns a BrowserHandle on success, nil and error string on failure.
--- opts:
---   browser_cmd: explicit absolute path to executable (overrides detection)
---   browser: friendly name hint (e.g. "chrome", "firefox")
---   on_exit: optional callback(job_id, exit_code)
---@param url string
---@param opts table|nil
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
    -- should not happen, but guard
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
    remove_tmp_profile(tmp)
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

--- Close a previously opened browser handle.
--- Attempts graceful stop via jobstop(); then removes temporary profile directory.
--- If there is no job handle (external opener used), this is a no-op.
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

  -- best-effort cleanup of temporary profile
  pcall(remove_tmp_profile, handle.tmp_profile)

  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

return M

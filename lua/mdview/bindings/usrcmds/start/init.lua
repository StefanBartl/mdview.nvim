---@module 'mdview.bindings.usrcmds.start'
--- Action behind :MDView start. Exposes configurable push strategy and wires
--- runner/session/autocmds/state. Registered as a composer route by
--- mdview.bindings.usrcmds (M.run takes the tokens after the "start" literal,
--- same shape :MDViewStart's raw fargs used to have).

local notify = require("lib.nvim.notify").create("").notify
local log = require("mdview.helper.log")
local state = require("mdview.core.state")
local session = require("mdview.core.session")
local autocmds = require("mdview.bindings.autocmds")
local normalize = require("mdview.helper.normalize")
local browser_defaults = require("mdview.config.browser").defaults
local start_defaults = require("mdview.config.usrcmd_start").defaults

local api = vim.api

-- strategy modules (lazy require later)
local launcher_mod_name = "mdview.bindings.usrcmds.start.server.launcher"
local trypush_mod_name = "mdview.bindings.usrcmds.start.server.try_push"

local M = {}

-- Parses :MDView start's space-separated args into an optional file path and
-- an optional cwd override, e.g.:
--   :MDView start file.md
--   :MDView start file.md cwd=C:/Users/bartl/
--   :MDView start cwd="c:/Users/bartl/"
-- The first non-`cwd=`-prefixed token is taken as the file path; surrounding
-- quotes on the cwd value (single or double) are stripped.
---@internal
---@param fargs string[]
---@return string|nil file, string|nil cwd
local function parse_start_args(fargs)
  local file, cwd, port
  for _, token in ipairs(fargs or {}) do
    local cwd_val = token:match("^cwd=(.+)$")
    local port_val = token:match("^port=(%d+)$")
    if cwd_val then
      cwd = cwd_val:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
    elseif port_val then
      -- `port=` rather than `--port`: `cwd=` is this command's existing
      -- convention, and one shape for both beats two.
      port = tonumber(port_val)
    elseif not file then
      file = token
    end
  end
  return file, cwd, port
end

-- initial_push_async: if an explicit path is provided (arg_path), prefer immediate try_push.
-- This allows `:MDViewStart /path/to/file.md` to immediately render that file into the preview.
---@internal
---@param push_strategy "launcher"|"try_push"
---@param try_push_opts table|nil
---@param wait_timeout integer|nil
---@param browser_opts table # { browser_autostart?: boolean, browser_cmd?: string, browser_args?: table, browser_url?: string }
---@param arg_path string|nil
---@return any|nil
local function initial_push_async(push_strategy, try_push_opts, wait_timeout, browser_opts, arg_path)
  -- perform push depending on chosen strategy; non-blocking

  -- if caller provided an explicit path, try immediate trypush (best-effort)
  if arg_path and arg_path ~= "" then
    local trypush = require(trypush_mod_name)
    local norm = normalize.path(arg_path)
    if not norm or norm == "" then
      log.debug("start: provided arg_path could not be normalized", nil, "usercmds.start", true)
      return
    end

    -- attempt to read buffer if open, else read file from disk
    local bufnr = vim.fn.bufnr(norm, false)
    local lines
    if bufnr and bufnr ~= -1 then
      lines = api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
    else
      -- safe file read fallback
      local ok, content = pcall(vim.fn.readfile, norm)
      if ok and content then
        lines = content
      else
        lines = {}
      end
    end

    trypush.try_push(norm, lines, try_push_opts)
    return
  end

  if push_strategy == "try_push" then
    local trypush = require(trypush_mod_name)
    local bufnr = api.nvim_get_current_buf()
    local raw_path = api.nvim_buf_get_name(bufnr)
    local path = normalize.path(raw_path)
    if not path or path == "" then
      log.debug("start: no normalized path for initial push", nil, "usercmds.start", true)
      return
    end
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
    trypush.try_push(path, lines, try_push_opts)
    return
  end

  -- default: launcher/waiter strategy
  local launcher = require(launcher_mod_name)
  local ok_browser = launcher.start({
    wait_timeout_ms = wait_timeout,
    browser_autostart = browser_opts.browser_autostart,
    browser_cmd = browser_opts.browser_cmd,
    browser_args = browser_opts.browser_args,
    -- forward explicit browser_url if present (launcher.resolve_browser_url will prefer it)
    browser_url = browser_opts.browser_url,
  })
  return ok_browser
end

--- Run the start action. Accepts an optional file path and an optional
--- `cwd=...` override, in either order, e.g.:
---   :MDView start
---   :MDView start file.md
---   :MDView start file.md cwd=C:/Users/bartl/
---   :MDView start cwd="c:/Users/bartl/"
--- (`fargs` is the token list after the "start" subcommand — composer's
--- `ctx.rest` — deliberately left as a free-form tail rather than a fixed
--- positional schema, since `cwd=` may appear before or after the file arg.)
---@param fargs string[]
---@return nil
function M.run(fargs)
  notify("[mdview] start invoked", vim.log.levels.DEBUG)

  local file_arg, cwd_arg, port_arg = parse_start_args(fargs)

  -- A fixed port for this run only, for the case the config key cannot
  -- serve: a firewall rule or a port-forward that has to match exactly, on
  -- one machine, without editing the config everyone else shares.
  --
  -- Applied to the live config rather than threaded through, because
  -- `adapter.server_args` reads `config.defaults.server_port` at spawn time
  -- and is several layers down. Restored after the spawn so it stays a
  -- one-run override -- otherwise the next plain `:MDView start` would
  -- silently inherit it.
  local config = require("mdview.config")
  local previous_port = config.defaults.server_port
  local function restore_port()
    if port_arg then
      config.defaults.server_port = previous_port
    end
  end
  if port_arg then
    if port_arg < 1 or port_arg > 65535 then
      notify(("[mdview] port=%d is out of range (1-65535)"):format(port_arg), vim.log.levels.WARN)
      return
    end
    config.defaults.server_port = port_arg
  end

  -- Server already running: don't re-spawn. Re-open the preview surface
  -- instead — the common reason to run :MDViewStart again is that the
  -- browser window was closed (without stopping the session) and the
  -- user wants it back. Always return from this branch: previously it
  -- fell through into the full start path, re-running session.init()
  -- (wiping snapshots) and the whole launcher against the live server.
  if state.get_server() then
    if cwd_arg then
      notify("[mdview] cwd=... ignored — server is already running", vim.log.levels.WARN)
    end
    if port_arg then
      notify("[mdview] port=... ignored — server is already running", vim.log.levels.WARN)
    end
    restore_port()

    -- optional explicit file arg: push that file's content first
    local arg_path = file_arg and file_arg ~= "" and file_arg or nil
    if arg_path then
      initial_push_async(start_defaults.push_strategy, start_defaults.try_push_opts, start_defaults.wait_timeout_ms, {
        browser_autostart = false, -- browser is (re)opened explicitly below
        browser_cmd = browser_defaults.browser_cmd or browser_defaults.resolved_browser_cmd,
        browser_args = browser_defaults.browser_args,
      }, arg_path)
    end

    -- re-open the preview surface for the current buffer
    if require("mdview.config").defaults.open_preview_tab then
      require("mdview.adapter.preview_tab").open(vim.api.nvim_get_current_buf())
    else
      require("mdview").open()
    end
    return
  end

  -- merge runtime config overrides (no mutation of module defaults)
  local push_strategy = start_defaults.push_strategy
  local try_push_opts = start_defaults.try_push_opts
  local wait_timeout = start_defaults.wait_timeout_ms
  local browser_opts = {
    browser_autostart = (browser_defaults.browser_autostart == nil) and browser_defaults.browser_autostart
      or browser_defaults.browser_autostart,
    browser_cmd = browser_defaults.browser_cmd or browser_defaults.resolved_browser_cmd,
    browser_args = browser_defaults.browser_args,
  }

  -- allow optional file argument: prefer the parsed file_arg when provided
  local initial_target = nil
  if file_arg and file_arg ~= "" then
    local norm = normalize.path(file_arg)
    initial_target = (norm and norm ~= "") and norm or file_arg
  end

  -- Ensure server proc spawned (cwd_arg, if given, overrides mdview.config.defaults.server_cwd for this spawn)
  local proc, proc_err = state.ensure_proc_started(cwd_arg)
  if not proc then
    notify("[mdview] failed to start server process" .. (proc_err and (": " .. proc_err) or ""), vim.log.levels.ERROR)
    return
  end
  -- Wire session + autocmds BEFORE marking the server as "running":
  -- if autocmds.attach() errors, we don't want state.get_server() left
  -- truthy (which would make every later :MDViewStart say "already
  -- running" against a never-fully-started session).
  session.init()
  autocmds.attach()
  state.set_server(proc)
  state.set_attached(true)

  -- perform chosen initial push strategy (non-blocking)
  initial_push_async(push_strategy, try_push_opts, wait_timeout, browser_opts, initial_target)

  -- The spawn has read server_port by now, so the override has done its job.
  restore_port()

  notify(port_arg and ("[mdview] started on port %d"):format(port_arg) or "[mdview] started", vim.log.levels.INFO)
  log.debug("usercmds.start: MDView start completed wiring", nil, "usercmds.start", true)
end

return M

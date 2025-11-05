---@module 'mdview.init'
-- Module entrypoint for mdview.nvim.
-- Integrates browser autostart handle storage and stop-time cleanup.

local cfg = require("mdview.config")
local browser_cfg = require("mdview.config.browser")
local runner = require("mdview.adapter.runner")
local events = require("mdview.core.events")
local session = require("mdview.core.session")
local autostart = require("mdview.usercommands.autostart")
local browser_adapter = require("mdview.adapter.browser")

local notify = vim.notify

local M = {}

M.config = cfg.defaults
M.state = {
  server = nil,   -- hold runner handle
  attached = false,
  browser = nil,  -- holds BrowserHandle
}

---@param opts table|nil
---@return nil
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    M.config[k] = v
  end

  require("mdview.config.browser").setup_and_notify() -- Resolve browser at setup time and notify user if resolution failed
  require("mdview.usercommands").setup()
  require("mdview.autocmds").setup()
end

-- Start mdview server, initialize session and attach events.
-- Side effects:
--   - attempts to start a server process via runner.start_server
--   - on success sets M.state.server to the returned process handle
--   - initializes session and attaches event handlers
--   - sets M.state.attached = true
--   - schedules autostart and may set M.state.browser if a browser handle is returned
--   - notifies the user on success or failure via notify
---@return nil
function M.start()
  if M.state.server then
    notify("mdview: server already running", vim.log.levels.INFO)
    return
  end

  local ok, handle_or_err = pcall(runner.start_server, M.config.server_cmd, M.config.server_args, M.config.server_cwd)
  if not ok or not handle_or_err then
    notify("mdview: failed to start server: " .. tostring(handle_or_err), vim.log.levels.ERROR)
    return
  end

  M.state.server = handle_or_err
  session.init()
  events.attach()
  M.state.attached = true

  -- Wait before open autostart tab and capture browser handle if any
  vim.defer_fn(function()
    local handle = autostart.start()
    if handle then
      M.state.browser = handle
    end
  end, 500)

  notify("[mdview] started", vim.log.levels.INFO)
end

-- If config.browser.stop_closes_browser is true (default), attempt to close stored browser handle.
-- Side effects:
--   - detaches autocommands via events.detach()
--   - stops the running server via runner.stop_server and clears M.state.server
--   - shuts down session via session.shutdown()
--   - optionally closes stored browser handle via browser_adapter.close()
--   - notifies the user of stop/failure via vim.notify
---@param close_browser_override boolean?  # when provided, explicitly control whether to close the browser handle; if nil, use browser_cfg.defaults.stop_closes_browser
---@return nil
function M.stop(close_browser_override)
  if M.state.attached then
    events.detach()
    M.state.attached = false
  end

  if M.state.server then
    pcall(runner.stop_server, M.state.server)
    M.state.server = nil
  end

  session.shutdown()

  local should_close
  if type(close_browser_override) == "boolean" then
    should_close = close_browser_override
  else
    should_close = browser_cfg.defaults.stop_closes_browser == true
  end

  if should_close and M.state.browser then
    local ok, err = browser_adapter.close(M.state.browser)
    if not ok then
      notify(("[mdview] failed to close browser: %s"):format(tostring(err)), vim.log.levels.WARN)
    end
    M.state.browser = nil
  end

  notify("[mdview] stopped", vim.log.levels.INFO)
end

-- ADD: testfunctions
-- Expose internals for REPL/testing
M._session = session
M._runner = runner
M._events = events
M._browser_adapter = browser_adapter

return M

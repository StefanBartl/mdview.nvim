---@module 'mdview.init'
--- Module entrypoint for mdview.nvim.
--- Integrates browser autostart handle storage and stop-time cleanup.
---
--- EmmyLua annotations available in module files.

local cfg = require("mdview.config")
local browser_cfg = require("mdview.config.browser")
local runner = require("mdview.adapter.runner")
local events = require("mdview.core.events")
local session = require("mdview.core.session")
local autostart = require("mdview.usercommands.autostart")
local browser_adapter = require("mdview.adapter.browser")

local M = {}

-- public state
M.config = cfg.defaults
M.state = {
  server = nil,   -- will hold runner handle
  attached = false,
  browser = nil,  -- holds BrowserHandle returned by browser_adapter.open()
}

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    M.config[k] = v
  end

  -- Resolve browser at setup time and notify user if resolution failed
  require("mdview.config.browser").setup_and_notify()
  require("mdview.usercommands").setup()
  require("mdview.autocmds").setup()
end

function M.start()
  if M.state.server then
    vim.notify("mdview: server already running", vim.log.levels.INFO)
    return
  end

  local ok, handle_or_err = pcall(runner.start_server, M.config.server_cmd, M.config.server_args, M.config.server_cwd)
  if not ok or not handle_or_err then
    vim.notify("mdview: failed to start server: " .. tostring(handle_or_err), vim.log.levels.ERROR)
    return
  end

  M.state.server = handle_or_err
  session.init()
  events.attach()
  M.state.attached = true

  -- Wait briefly, then open autostart tab and capture browser handle (if any)
  vim.defer_fn(function()
    local handle = autostart.start()
    if handle then
      M.state.browser = handle
    end
  end, 500)

  vim.notify("mdview: started", vim.log.levels.INFO)
end

--- Stop mdview environment: detach autocommands and stop server if running.
--- If config.browser.stop_closes_browser is true (default), attempt to close stored browser handle.
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
      vim.notify(("mdview: failed to close browser: %s"):format(tostring(err)), vim.log.levels.WARN)
    end
    M.state.browser = nil
  end

  vim.notify("mdview: stopped", vim.log.levels.INFO)
end

-- Expose internals for REPL/testing
M._session = session
M._runner = runner
M._events = events
M._browser_adapter = browser_adapter

return M

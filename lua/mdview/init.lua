---@module 'mdview.init'
--- Module entrypoint for mdview.nvim.
--- Exposes a minimal setup() API plus start/stop runtime controls used by plugin commands.

local config = require("mdview.config")
local runner = require("mdview.adapter.runner")
local events = require("mdview.core.events")
local session = require("mdview.core.session")

local M = {}

-- public state
M.config = config.defaults
M.state = {
  server = nil,   -- will hold runner handle
  attached = false,
}

--- Setup function for user configuration (not needed for dev-opt; placeholder).
--- Accepts a table with allowed overrides; merges into default config.
---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    M.config[k] = v
  end
end

--- Start mdview environment: spawn server, attach autocommands and prepare session.
function M.start()
  if M.state.server then
    vim.notify("mdview: server already running", vim.log.levels.INFO)
    return
  end

  -- spawn server (runner returns handle table or nil + error)
  local ok, handle_or_err = pcall(runner.start_server, M.config.server_cmd, M.config.server_args)
  if not ok or not handle_or_err then
    vim.notify("mdview: failed to start server: " .. tostring(handle_or_err), vim.log.levels.ERROR)
    return
  end
  M.state.server = handle_or_err

  -- initialize session store
  session.init()

  -- attach autocommands
  events.attach()

  M.state.attached = true
  vim.notify("mdview: started", vim.log.levels.INFO)
end

--- Stop mdview environment: detach autocommands and stop server if running.
function M.stop()
  if M.state.attached then
    events.detach()
    M.state.attached = false
  end

  if M.state.server then
    pcall(runner.stop_server, M.state.server)
    M.state.server = nil
  end

  session.shutdown()
  vim.notify("mdview: stopped", vim.log.levels.INFO)
end

-- For testing / REPL
M._session = session
M._runner = runner
M._events = events

return M

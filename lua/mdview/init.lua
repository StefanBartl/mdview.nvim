---@module 'mdview.init'
-- Module entrypoint for mdview.nvim.
-- Integrates browser autostart handle storage and stop-time cleanup.

local cfg = require("mdview.config")
local runner = require("mdview.adapter.runner")
local events = require("mdview.core.events")
local session = require("mdview.core.session")
local browser_adapter = require("mdview.adapter.browser")

local M = {}

M.config = cfg.defaults

---@param opts table|nil
---@return nil
function M.setup(opts)
	opts = opts or {}
	for k, v in pairs(opts) do
		M.config[k] = v
	end

	-- Resolve browser at setup time and notify user if resolution failed
	require("mdview.config.browser").setup_and_notify()
	require("mdview.usercmds").attach()
end

-- ADD: testfunctions
-- Expose internals for REPL/testing
M._session = session
M._runner = runner
M._events = events
M._browser_adapter = browser_adapter

return M

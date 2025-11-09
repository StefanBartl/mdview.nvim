---@module 'mdview.usercmds.stop'
-- Side effects:
-- If config.browser.stop_closes_browser is true (default), attempt to close stored browser handle.
--   - detaches autocommands via events.detach()
--   - stops the running server via runner.stop_server and clears state.server
--   - shuts down session via session.shutdown()
--   - optionally closes stored browser handle via browser_adapter.close()
--   - notifies the user of stop/failure via vim.notify
-- ADD: Annotations noch korrekt?

local browser_cfg = require("mdview.config.browser")
local runner = require("mdview.adapter.runner")
local session = require("mdview.core.session")
local autocmds = require("mdview.autocmds")
local browser_adapter = require("mdview.adapter.browser")
local usercmds_registry = require("mdview.helper.usercmds_registry")
local state = require("mdview.core.state")
local notify = vim.notify

local M = {}

function M.attach()
  local opts = {
		desc = "[mdview] Stop mdview preview server and detach autocommands",
		nargs = 0,
  }

	usercmds_registry.register("MDViewStop", function()
		pcall(M.stop, browser_cfg.defaults.browser_autoclose)
	end, opts)
end

---@param close_browser_override boolean?  # when provided, explicitly control whether to close the browser handle; if nil, use browser_cfg.defaults.browser_autoclose
---@return nil
function M.stop(close_browser_override)
  if state.is_attached() then
    pcall(autocmds.teardown)
    state.set_attached(false)
  end

	if state.get_server() then
		pcall(runner.stop_server, state.get_server())
		state.set_server(nil)
	end

	session.shutdown()

	local should_close
	if type(close_browser_override) == "boolean" then
		should_close = close_browser_override
	else
		should_close = browser_cfg.defaults.browser_autoclose == true
	end

	if should_close and state.get_browser() then
		local ok, err = browser_adapter.close(state.get_browser())
		if not ok then
			notify(("[mdview] failed to close browser: %s"):format(tostring(err)), vim.log.levels.WARN)
		end
		state.set_browser(nil)
	end

	require("mdview.helper.usercmds_registry").detach_all() -- AUDIT: Derzeit nur `:MDViewStop` registriert
	require("mdview.helper.autocmds_registry").detach_all()
	notify("[mdview] stopped", vim.log.levels.INFO)
end

return M

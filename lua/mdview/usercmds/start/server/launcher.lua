---@module 'mdview.usercmds.start.server.launcher'
--- Lightweight launcher for server autostart.
--- Uses ws_client.wait_ready as primary readiness mechanism and triggers single initial push.

local runner = require("mdview.adapter.runner")
local ws_client = require("mdview.adapter.ws_client")
local live_push = require("mdview.autocmds.live_push")
local browser_adapter = require("mdview.adapter.browser")
local session = require("mdview.core.session")
local autocmds = require("mdview.autocmds")
local state = require("mdview.core.state")
local log = require("mdview.helper.log")

local api = vim.api
local notify = vim.notify
local schedule = vim.schedule

local M = {}
local SERVER_URL = "http://localhost:" .. tostring(require("mdview.config.init").defaults.server_port or 43219)

--- Start server and perform a single wait_ready -> initial push.
--- Returns browser handle if launched, otherwise nil.
--- @param opts table|nil  # { wait_timeout_ms?: integer, browser_autostart?: boolean, browser_args?: table }
--- @return any|nil
function M.start(opts)
	opts = opts or {}
	local wait_timeout = opts.wait_timeout_ms or ws_client.WAIT_READY_TIMEOUT or 2000
	local browser_autostart = (opts.browser_autostart == nil)
			and require("mdview.config.browser").defaults.browser_autostart
		or opts.browser_autostart
	local browser_cmd = opts.browser_cmd or require("mdview.config.browser").defaults.resolved_browser_cmd
	local browser_args = opts.browser_args

	-- ensure no previous running instance in runner
	if runner.is_running() then
		runner.stop_server(runner.proc)
	end

	-- spawn server using configured command (uses runner.resolve logic)
	local proc = runner.start_server(
		require("mdview.config.init").defaults.server_cmd,
		require("mdview.config.init").defaults.server_args,
		require("mdview.config.init").defaults.server_cwd
	)
	if not proc then
		notify("[mdview] failed to spawn server process", vim.log.levels.ERROR)
		return nil
	end

	-- attach session & autocmds after successful spawn
	session.init()
	autocmds.attach()
	state.set_attached(true)
	state.set_server(proc)

	-- optionally open browser immediately (best-effort)
	local browser_handle = nil
	if browser_autostart and browser_adapter and browser_adapter.open then
		-- construct options table for browser.open
		local opts_table = {
			browser_cmd = browser_cmd,
			browser_args = browser_args,
			on_exit = function(_, code)
				log.debug(("browser exited with code %s"):format(tostring(code)), nil, "launcher", true)
			end,
		}

		local ok, handle_or_err = pcall(browser_adapter.open, SERVER_URL, opts_table)
		if ok and handle_or_err then
			browser_handle = handle_or_err
			state.set_browser(browser_handle)
			log.debug("launcher: browser autostart successful", nil, "launcher", true)
		else
			schedule(function()
				notify(("[mdview.usercmds] browser adapter failed: %s"):format(tostring(handle_or_err)), vim.log.levels.WARN)
			end)
		end
	end

	-- Wait for server health and perform a single immediate full push on readiness
	ws_client.wait_ready(function(ok)
		if ok then
			schedule(function()
				log.debug("launcher: server ready — performing initial full push", nil, "launcher", true)
				local buf = api.nvim_get_current_buf()
				live_push.attach() -- ensure live_push autocmds are installed (idempotent)
				live_push.push_buffer_changes(buf, true)
			end)
		else
			schedule(function()
				notify(
					"[mdview.usercmds] Server health-check failed; preview may not update automatically",
					vim.log.levels.WARN
				)
			end)
		end
	end, wait_timeout)

	return browser_handle
end

return M

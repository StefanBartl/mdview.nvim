---@module 'mdview.usercmds.start.server.launcher'
--- Lightweight launcher for server autostart.
--- Uses ws_client.wait_ready as primary readiness mechanism and triggers single initial push.

--AUDIT: Modularisieren

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
-- local SERVER_URL = "http://localhost:" .. tostring(require("mdview.config.init").defaults.server_port or 43219)

-- prefer a client dev server URL when available, fallback to backend server
---@param opts table|nil
---@return string
local function resolve_browser_url(opts)
	opts = opts or {}

	-- explicit override (useful for tests or external launchers)
	if type(opts.browser_url) == "string" and opts.browser_url ~= "" then
		return opts.browser_url
	end

	local res
	-- check if the dev server port was captured from runner logs
	if vim.g.mdview_dev_port and vim.g.mdview_dev_port > 0 then
		res = ("http://localhost:%d/"):format(vim.g.mdview_dev_port)
		vim.notify("DEBUG mdview_dev_port Browser URL: " .. res, 2)
		return res
	end

	-- fallback to configured dev_server_port (from browser config)
	local browser_defaults = require("mdview.config.browser").defaults
	if browser_defaults.dev_server_port and browser_defaults.dev_server_port > 0 then
		res = ("http://localhost:%d/"):format(browser_defaults.dev_server_port)
		vim.notify("DEBUG browser_defaults Browser URL: " .. res, 2)
		return res
	end

	-- finally fallback to backend server port (for production)
	local server_port = require("mdview.config").defaults.server_port or 43219
	res = ("http://localhost:%d/"):format(server_port)
	vim.notify("DEBUG Fallback Browser URL: " .. res, 2)
	return res
end

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
	if state.proc_is_running() then
		runner.stop_server(state.get_proc())
	end

	-- spawn server using configured command (uses runner.resolve logic)
	local proc = runner.start_server(
		require("mdview.config").defaults.server_cmd,
		require("mdview.config").defaults.server_args,
		require("mdview.config").defaults.server_cwd
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

		local browser_url = resolve_browser_url({ browser_url = opts.browser_url })

		local ok, handle_or_err = pcall(browser_adapter.open, browser_url, opts_table)
		if ok and handle_or_err then
			browser_handle = handle_or_err
			state.set_browser(browser_handle)
			log.debug("launcher: browser autostart successful", nil, "launcher", true)
		else
			schedule(function()
				notify(
					("[mdview.usercmds] browser adapter failed: %s"):format(tostring(handle_or_err)),
					vim.log.levels.WARN
				)
			end)
		end
	end

	-- Wait for server health and perform a single immediate full push on readiness
	ws_client.wait_ready(function(ok)
		if ok then
			local port = vim.g.mdview_server_port or 43219
			vim.g.mdview_server_port = port
			vim.notify("[mdview] detected server port: " .. tostring(port), 2)

			schedule(function()
				log.debug("launcher: server ready — performing initial full push", nil, "launcher", true)
				local buf = api.nvim_get_current_buf()
				live_push.attach() -- ensure live_push autocmds are installed (idempotent)
				live_push.push_buffer_changes(buf, true)

				-- open browser after readiness (best-effort)
				if browser_autostart and browser_adapter and browser_adapter.open then
					local browser_url = resolve_browser_url({ browser_url = opts.browser_url })
					local opts_table = {
						browser_cmd = browser_cmd,
						browser_args = browser_args,
						on_exit = function(_, code)
							log.debug(("browser exited with code %s"):format(tostring(code)), nil, "launcher", true)
						end,
					}
					local ok2, handle_or_err = pcall(browser_adapter.open, browser_url, opts_table)
					if ok2 and handle_or_err then
						state.set_browser(handle_or_err)
						log.debug("launcher: browser autostart successful (post-ready)", nil, "launcher", true)
					else
						notify(
							("[mdview.usercmds] browser adapter failed: %s"):format(tostring(handle_or_err)),
							vim.log.levels.WARN
						)
					end
				end
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

	return true
end

return M

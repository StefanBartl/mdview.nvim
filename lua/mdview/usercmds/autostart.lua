---@module 'mdview.usercmds.autostart'
--- Autostart helper: start server and open preview. Integrates with mdview.adapter.browser when available.
--- Returns browser handle when it started a controllable browser instance, otherwise nil.

---@diagnostic disable: undefined-field, deprecated, undefined-global, unused-local, return-type-mismatch

local runner = require("mdview.adapter.runner")
local live_push = require("mdview.autocmds.live_push")
local api = vim.api
local notify = vim.notify
local schedule = vim.schedule
local nvim_create_autocmd = api.nvim_create_autocmd
local ws_client = require("mdview.adapter.ws_client")
local browser_adapter = require("mdview.adapter.browser")

local M = {}
local SERVER_URL = "http://localhost:43219"

M.wait_for_ready = true -- whether to wait for server before opening preview

-- Main autostart function: starts server and opens browser/preview.
-- Returns browser handle if a controllable instance was started, otherwise nil.
---@param wait boolean|nil whether to wait for server before sending
function M.start(wait)
	wait = (wait == nil) and M.wait_for_ready or wait

	-- restart server if already running
	if runner.is_running() then
		runner.stop_server(runner.proc)
	end

	runner.start_server("npm", { "run", "dev:server" })

	-- open browser if adapter available
	local handle, err = browser_adapter.open(SERVER_URL)
	if not handle and err then
		schedule(function()
			notify(("[mdview.usercommands] browser adapter: %s"):format(tostring(err)), vim.log.levels.WARN)
		end)
	end

	-- wait for server ready if requested
	if wait then
		ws_client.wait_ready(function(ok)
			if ok then
				schedule(function()
					notify("[mdview.usercommands] Server ready, sending current buffer...", vim.log.levels.INFO)
					local buf = api.nvim_get_current_buf()
					live_push.setup()
					-- push full buffer immediately (initial push)
					live_push.push_buffer_changes(buf, true)
				end)
			else
				schedule(function()
					notify(
						"[mdview.usercommands] Server health-check failed, preview may not update automatically",
						vim.log.levels.WARN
					)
				end)
			end
		end)
	end

	return handle
end

return M

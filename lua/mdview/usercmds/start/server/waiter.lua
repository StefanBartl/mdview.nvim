---@module 'mdview.usercmds.start.server.waiter'
--- Thin wrapper around ws_client.wait_ready that exposes simple promise-like behavior
--- and a blocking-style helper that calls a callback when ready or when timeout reached.

local ws_client = require("mdview.adapter.ws_client")
local log = require("mdview.helper.log")
local M = {}

--- Wait for server ready and call cb(ok)
--- @param cb fun(ok:boolean)
--- @param timeout_ms integer|nil
function M.wait(cb, timeout_ms)
	-- delegate to existing ws_client.wait_ready
	ws_client.wait_ready(function(ok)
		if not ok then
			log.debug("waiter: server not ready within timeout", nil, "waiter", true)
		end
		if type(cb) == "function" then
			pcall(cb, ok)
		end
	end, timeout_ms)
end

return M

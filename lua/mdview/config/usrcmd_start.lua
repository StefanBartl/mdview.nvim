---@moddule 'mdview-config.usrcmd_start'

local M = {}

--- configuration defaults for the usercommand module
--- @type table
M.defaults = {
	push_strategy = "launcher", -- "launcher" | "try_push"
	try_push_opts = nil, -- forwarded to try_push when used
	wait_timeout_ms = nil, -- forwarded to launcher.wait_ready
	browser_autostart = nil,
	browser_cmd = nil,
	browser_args = nil,
}

return M

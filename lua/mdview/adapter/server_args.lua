---@module 'mdview.adapter.server_args'
-- Resolves the (cmd, args, cwd) triple used to spawn the native
-- mdview-server process: ensures the platform binary and client bundle are
-- installed, generates a fresh per-session token, and stores it in state so
-- ws_client can attach it to /update and the browser tab can attach it to /ws.

local install = require("mdview.adapter.install")
local gen_token = require("mdview.helper.gen_token")

local M = {}

--- @return string|nil cmd
--- @return string[]|nil args
--- @return string|nil cwd
--- @return string|nil err
function M.resolve()
	local defaults = require("mdview.config").defaults
	local state = require("mdview.core.state")

	local bin_path, bin_err = install.ensure_binary()
	if not bin_path then
		return nil, nil, nil, "failed to install mdview-server binary: " .. tostring(bin_err)
	end

	local web_root, web_err = install.ensure_client_bundle()
	if not web_root then
		return nil, nil, nil, "failed to install mdview client bundle: " .. tostring(web_err)
	end

	local token = gen_token()
	state.set_token(token)

	local args = {
		"--port",
		tostring(defaults.server_port or 43219),
		"--token",
		token,
		"--web-root",
		web_root,
	}

	return bin_path, args, defaults.server_cwd, nil
end

return M

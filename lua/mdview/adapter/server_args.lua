---@module 'mdview.adapter.server_args'
-- Resolves the (cmd, args, cwd) triple used to spawn the native
-- mdview-server process: ensures the platform binary and client bundle are
-- installed, generates a fresh per-session token, and stores it in state so
-- ws_client can attach it to /update and the browser tab can attach it to /ws.

local install = require("mdview.adapter.install")
local gen_token = require("mdview.helper.gen_token")

local M = {}

--- Relay binary the normal `:MDView start` path spawns: `dev.binary_path` if
--- configured, else `$MDVIEW_DEV_BINARY` (the only way a detached instance —
--- scripts/minimal_init.lua loads none of the user's Lua config — can reach
--- one), else whatever `install` manages.
---@return string|nil path, string|nil err
local function resolve_binary()
	local dev = require("mdview.config").defaults.dev or {}
	local override = dev.binary_path
	if not (type(override) == "string" and override ~= "") then
		override = vim.env.MDVIEW_DEV_BINARY
	end
	if type(override) == "string" and override ~= "" then
		local path = vim.fn.expand(override)
		if vim.fn.executable(path) ~= 1 then
			return nil, "dev.binary_path is not executable: " .. path
		end
		return path, nil
	end
	return install.ensure_binary()
end

--- Client bundle dir the normal `:MDView start` path passes as --web-root:
--- `dev.web_root` if configured, else `$MDVIEW_DEV_WEB_ROOT`, else whatever
--- `install` manages. See resolve_binary for why the env var fallback exists.
---@return string|nil path, string|nil err
local function resolve_web_root()
	local dev = require("mdview.config").defaults.dev or {}
	local override = dev.web_root
	if not (type(override) == "string" and override ~= "") then
		override = vim.env.MDVIEW_DEV_WEB_ROOT
	end
	if type(override) == "string" and override ~= "" then
		local path = vim.fn.expand(override)
		if vim.fn.isdirectory(path) ~= 1 then
			return nil, "dev.web_root is not a directory: " .. path
		end
		return path, nil
	end
	return install.ensure_client_bundle()
end

--- @param cwd_override string|nil # takes precedence over mdview.config.defaults.server_cwd, e.g. from `:MDViewStart cwd=...`
--- @return string|nil cmd
--- @return string[]|nil args
--- @return string|nil cwd
--- @return string|nil err
function M.resolve(cwd_override)
	local defaults = require("mdview.config").defaults
	local state = require("mdview.core.state")

	local bin_path, bin_err = resolve_binary()
	if not bin_path then
		return nil, nil, nil, "failed to resolve mdview-server binary: " .. tostring(bin_err)
	end

	local web_root, web_err = resolve_web_root()
	if not web_root then
		return nil, nil, nil, "failed to resolve mdview client bundle: " .. tostring(web_err)
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

	-- Opt-in WebTransport (HTTP/3): ask the relay to also serve /wt and print its
	-- cert hash (the runner parses it). Off by default → no UDP listener / no
	-- cert overhead.
	local experimental = defaults.experimental or {}
	if experimental.webtransport == true then
		args[#args + 1] = "--webtransport"
	end

	local cwd = cwd_override
	if not cwd or cwd == "" then
		cwd = defaults.server_cwd
	end

	return bin_path, args, cwd, nil
end

return M

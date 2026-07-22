---@module 'mdview.adapter.server_args'
-- Resolves the (cmd, args, cwd) triple used to spawn the native
-- mdview-server process: ensures the platform binary and client bundle are
-- installed, generates a fresh per-session token, and stores it in state so
-- ws_client can attach it to /update and the browser tab can attach it to /ws.

local install = require("mdview.adapter.install")
local gen_token = require("mdview.helper.gen_token")

local M = {}

-- Developer-only override: a locally built relay binary / client bundle to use
-- instead of the downloaded `install.version` release, so features newer than
-- the pinned release (e.g. the /control channel behind :MDViewOverlay /
-- :MDViewZoom / :MDViewCursor) actually run. Resolved from defaults.dev, then
-- the MDVIEW_DEV_BINARY / MDVIEW_DEV_WEB_ROOT env vars; nil means "use the
-- release install manages" (the normal end-user path). Missing files are
-- reported rather than silently ignored, so a stale path fails loudly.
---@param configured string|nil
---@param env_name string
---@param what string # "binary" | "web-root", for the error message
---@return string|nil path, string|nil err
local function dev_override(configured, env_name, what)
	local raw = configured
	if type(raw) ~= "string" or raw == "" then
		raw = os.getenv(env_name)
	end
	if type(raw) ~= "string" or raw == "" then
		return nil, nil
	end
	local path = vim.fn.expand(raw)
	local exists = what == "web-root" and vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1
	if not exists then
		return nil, ("dev %s override does not exist: %s"):format(what, path)
	end
	return path, nil
end

--- @param cwd_override string|nil # takes precedence over mdview.config.defaults.server_cwd, e.g. from `:MDViewStart cwd=...`
--- @return string|nil cmd
--- @return string[]|nil args
--- @return string|nil cwd
--- @return string|nil err
function M.resolve(cwd_override)
	local defaults = require("mdview.config").defaults
	local state = require("mdview.core.state")
	local dev = defaults.dev or {}

	local bin_path, bin_err = dev_override(dev.binary_path, "MDVIEW_DEV_BINARY", "binary")
	if bin_err then
		return nil, nil, nil, bin_err
	end
	if not bin_path then
		bin_path, bin_err = install.ensure_binary()
		if not bin_path then
			return nil, nil, nil, "failed to install mdview-server binary: " .. tostring(bin_err)
		end
	end

	local web_root, web_err = dev_override(dev.web_root, "MDVIEW_DEV_WEB_ROOT", "web-root")
	if web_err then
		return nil, nil, nil, web_err
	end
	if not web_root then
		web_root, web_err = install.ensure_client_bundle()
		if not web_root then
			return nil, nil, nil, "failed to install mdview client bundle: " .. tostring(web_err)
		end
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

---@module 'mdview.usercmds.start'
--- User command entrypoint for :MDViewStart.
--- Exposes configurable push strategy and wires runner/session/autocmds/state.

local nvim_create_user_command = vim.api.nvim_create_user_command
local notify = vim.notify
local log = require("mdview.helper.log")
local runner = require("mdview.adapter.runner")
local state = require("mdview.core.state")
local session = require("mdview.core.session")
local autocmds = require("mdview.autocmds")
local normalize = require("mdview.helper.normalize")
local browser_cfg = require("mdview.config.browser").defaults
local cfg = require("mdview.config.init").defaults
local api = vim.api

-- strategy modules (lazy require later)
local launcher_mod_name = "mdview.usercmds.start.server.launcher"
local trypush_mod_name = "mdview.usercmds.start.server.try_push"

local M = {}

--- configuration defaults for the usercommand module
--- @type table
M.config = {
	push_strategy = "auncher", -- "launcher" | "try_push"
	try_push_opts = nil, -- forwarded to try_push when used
	wait_timeout_ms = nil, -- forwarded to launcher.wait_ready
	browser_autostart = nil,
	browser_cmd = nil,
	browser_args = nil,
}

local function ensure_proc_started()
	-- spawn server process if not already running via runner API
	if runner.is_running() then
		return runner.proc
	end
	local proc = runner.start_server(cfg.server_cmd, cfg.server_args, cfg.server_cwd)
	return proc
end

local function initial_push_async(push_strategy, try_push_opts, wait_timeout, browser_opts)
	-- perform push depending on chosen strategy; non-blocking
	if push_strategy == "try_push" then
		local trypush = require(trypush_mod_name)
		local bufnr = api.nvim_get_current_buf()
		local raw_path = api.nvim_buf_get_name(bufnr)
		local path = normalize.path(raw_path)
		if not path or path == "" then
			log.debug("start: no normalized path for initial push", nil, "usercmds.start", true)
			return
		end
		local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
		trypush.try_push(path, lines, try_push_opts)
		return
	end

	-- default: launcher/waiter strategy
	local launcher = require(launcher_mod_name)
	local ok_browser = launcher.start({
		wait_timeout_ms = wait_timeout,
		browser_autostart = browser_opts.browser_autostart,
		browser_cmd = browser_opts.browser_cmd,
		browser_args = browser_opts.browser_args,
	})
	return ok_browser
end

--- Register :MDViewStart user command.
--- Options:
---   - opts table may override M.config at runtime.
---   - accepted push_strategy values: "launcher" (default) | "try_push"
function M.attach()
	nvim_create_user_command("MDViewStart", function(cmdopts)
		notify("[mdview] MDViewStart invoked", vim.log.levels.DEBUG)

		-- If server already present in state, just noop with message
		if state.get_server() then
			notify("[mdview] server already running", vim.log.levels.INFO)
			return
		end

		-- merge runtime config overrides (no mutation of module defaults)
		local push_strategy = M.config.push_strategy
		local try_push_opts = M.config.try_push_opts
		local wait_timeout = M.config.wait_timeout_ms
		local browser_opts = {
			browser_autostart = (M.config.browser_autostart == nil) and browser_cfg.browser_autostart
				or M.config.browser_autostart,
			browser_cmd = M.config.browser_cmd or browser_cfg.resolved_browser_cmd,
			browser_args = M.config.browser_args,
		}

		-- Ensure server proc spawned
		local proc = ensure_proc_started()
		if not proc then
			notify("[mdview] failed to start server process", vim.log.levels.ERROR)
			return
		end
		state.set_server(proc)
		session.init()
		autocmds.attach()
		state.set_attached(true)

		-- perform chosen initial push strategy (non-blocking)
		initial_push_async(push_strategy, try_push_opts, wait_timeout, browser_opts)

		notify("[mdview] started", vim.log.levels.INFO)
		log.debug("usercmds.start: MDViewStart completed wiring", nil, "usercmds.start", true)
	end, {
		desc = "[mdview] Start mdview preview server and attach autocommands",
		nargs = 0,
	})
end

return M

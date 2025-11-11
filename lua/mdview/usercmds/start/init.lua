---@module 'mdview.usercmds.start'
--- User command entrypoint for :MDViewStart.
--- Exposes configurable push strategy and wires runner/session/autocmds/state.

local nvim_create_user_command = vim.api.nvim_create_user_command
local notify = vim.notify
local log = require("mdview.helper.log")
local state = require("mdview.core.state")
local session = require("mdview.core.session")
local autocmds = require("mdview.autocmds")
local normalize = require("mdview.helper.normalize")
local browser_defaults = require("mdview.config.browser").defaults
local start_defaults = require("mdview.config.usrcmd_start").defaults

local api = vim.api

-- strategy modules (lazy require later)
local launcher_mod_name = "mdview.usercmds.start.server.launcher"
local trypush_mod_name = "mdview.usercmds.start.server.try_push"

local M = {}

-- initial_push_async: if an explicit path is provided (arg_path), prefer immediate try_push.
-- This allows `:MDViewStart /path/to/file.md` to immediately render that file into the preview.
local function initial_push_async(push_strategy, try_push_opts, wait_timeout, browser_opts, arg_path)
	-- perform push depending on chosen strategy; non-blocking

	-- if caller provided an explicit path, try immediate trypush (best-effort)
	if arg_path and arg_path ~= "" then
		local trypush = require(trypush_mod_name)
		local norm = normalize.path(arg_path)
		if not norm or norm == "" then
			log.debug("start: provided arg_path could not be normalized", nil, "usercmds.start", true)
			return
		end

		-- attempt to read buffer if open, else read file from disk
		local bufnr = vim.fn.bufnr(norm, false)
		local lines = nil
		if bufnr and bufnr ~= -1 then
			lines = api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
		else
			-- safe file read fallback
			local ok, content = pcall(vim.fn.readfile, norm)
			if ok and content then
				lines = content
			else
				lines = {}
			end
		end

		trypush.try_push(norm, lines, try_push_opts)
		return
	end

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
		-- forward explicit browser_url if present (launcher.resolve_browser_url will prefer it)
		browser_url = browser_opts.browser_url,
	})
	return ok_browser
end

--- Register :MDViewStart user command.
--- Accepts optional single file argument to target a specific markdown file.
--- Options:
---   - opts table may override M.config at runtime.
---   - accepted push_strategy values: "launcher" (default) | "try_push"
function M.attach()
	-- allow optional file arg; nargs='?' and complete='file' helps UX
	nvim_create_user_command("MDViewStart", function(cmdopts)
		notify("[mdview] MDViewStart invoked", vim.log.levels.DEBUG)

		-- If server already present in state, just noop with message
		if state.get_server() then
			notify("[mdview] server already running", vim.log.levels.INFO)
			-- still allow initial push when server already running and arg provided
			local arg_path = cmdopts.args and cmdopts.args ~= "" and cmdopts.args or nil
			if arg_path then
				initial_push_async(
					start_defaults.push_strategy,
					start_defaults.try_push_opts,
					start_defaults.wait_timeout_ms,
					{
						browser_autostart = (browser_defaults.browser_autostart == nil)
								and browser_defaults.browser_autostart
							or browser_defaults.browser_autostart,
						browser_cmd = browser_defaults.browser_cmd or browser_defaults.resolved_browser_cmd,
						browser_args = browser_defaults.browser_args,
						-- set browser_url from browser config dev_server_port if present (preferred in dev_local)
						browser_url = (browser_defaults.dev_server_port and ("http://localhost:" .. tostring(
							browser_defaults.dev_server_port
						) .. "/")) or nil,
					},
					arg_path
				)
			else
				return
			end
		end

		-- merge runtime config overrides (no mutation of module defaults)
		local push_strategy = start_defaults.push_strategy
		local try_push_opts = start_defaults.try_push_opts
		local wait_timeout = start_defaults.wait_timeout_ms
		local browser_opts = {
			browser_autostart = (browser_defaults.browser_autostart == nil) and browser_defaults.browser_autostart
				or browser_defaults.browser_autostart,
			browser_cmd = browser_defaults.browser_cmd or browser_defaults.resolved_browser_cmd,
			browser_args = browser_defaults.browser_args,
		}

		-- allow optional file argument: prefer cmdopts.args when provided
		local initial_target = nil
		if cmdopts and cmdopts.args and cmdopts.args ~= "" then
			local raw = cmdopts.args
			local norm = normalize.path(raw)
			initial_target = (norm and norm ~= "") and norm or raw
		end

		-- Ensure server proc spawned
		local proc = state.ensure_proc_started()
		if not proc then
			notify("[mdview] failed to start server process", vim.log.levels.ERROR)
			return
		end
		state.set_server(proc)
		session.init()
		autocmds.attach()
		state.set_attached(true)

		-- perform chosen initial push strategy (non-blocking)
		initial_push_async(push_strategy, try_push_opts, wait_timeout, browser_opts, initial_target)

		notify("[mdview] started", vim.log.levels.INFO)
		log.debug("usercmds.start: MDViewStart completed wiring", nil, "usercmds.start", true)
	end, {
		desc = "[mdview] Start mdview preview server and attach autocommands (optional file arg)",
		nargs = "?",
		complete = "file",
	})
end

return M

---@module 'mdview.bindings.usrcmds.start'
--- User command entrypoint for :MDViewStart.
--- Exposes configurable push strategy and wires runner/session/autocmds/state.

local libusercmd = require("lib.nvim.usercmd")
local notify = vim.notify
local log = require("mdview.helper.log")
local state = require("mdview.core.state")
local session = require("mdview.core.session")
local autocmds = require("mdview.bindings.autocmds")
local normalize = require("mdview.helper.normalize")
local browser_defaults = require("mdview.config.browser").defaults
local start_defaults = require("mdview.config.usrcmd_start").defaults

local api = vim.api

-- strategy modules (lazy require later)
local launcher_mod_name = "mdview.bindings.usrcmds.start.server.launcher"
local trypush_mod_name = "mdview.bindings.usrcmds.start.server.try_push"

local M = {}

-- Parses :MDViewStart's space-separated args into an optional file path and
-- an optional cwd override, e.g.:
--   :MDViewStart file.md
--   :MDViewStart file.md cwd=C:/Users/bartl/
--   :MDViewStart cwd="c:/Users/bartl/"
-- The first non-`cwd=`-prefixed token is taken as the file path; surrounding
-- quotes on the cwd value (single or double) are stripped.
---@param fargs string[]
---@return string|nil file, string|nil cwd
local function parse_start_args(fargs)
	local file, cwd
	for _, token in ipairs(fargs or {}) do
		local cwd_val = token:match("^cwd=(.+)$")
		if cwd_val then
			cwd = cwd_val:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
		elseif not file then
			file = token
		end
	end
	return file, cwd
end

-- initial_push_async: if an explicit path is provided (arg_path), prefer immediate try_push.
-- This allows `:MDViewStart /path/to/file.md` to immediately render that file into the preview.
---@param push_strategy "launcher"|"try_push"
---@param try_push_opts table|nil
---@param wait_timeout integer|nil
---@param browser_opts table # { browser_autostart?: boolean, browser_cmd?: string, browser_args?: table, browser_url?: string }
---@param arg_path string|nil
---@return any|nil
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
		local lines
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
--- Accepts an optional file path and an optional `cwd=...` override, in
--- either order, e.g.:
---   :MDViewStart
---   :MDViewStart file.md
---   :MDViewStart file.md cwd=C:/Users/bartl/
---   :MDViewStart cwd="c:/Users/bartl/"
--- Options:
---   - opts table may override M.config at runtime.
---   - accepted push_strategy values: "launcher" (default) | "try_push"
function M.attach()
	libusercmd.create("MDViewStart", function(cmdopts)
		notify("[mdview] MDViewStart invoked", vim.log.levels.DEBUG)

		local file_arg, cwd_arg = parse_start_args(cmdopts.fargs)

		-- Server already running: don't re-spawn. Re-open the preview surface
		-- instead — the common reason to run :MDViewStart again is that the
		-- browser window was closed (without stopping the session) and the
		-- user wants it back. Always return from this branch: previously it
		-- fell through into the full start path, re-running session.init()
		-- (wiping snapshots) and the whole launcher against the live server.
		if state.get_server() then
			if cwd_arg then
				notify("[mdview] cwd=... ignored — server is already running", vim.log.levels.WARN)
			end

			-- optional explicit file arg: push that file's content first
			local arg_path = file_arg and file_arg ~= "" and file_arg or nil
			if arg_path then
				initial_push_async(
					start_defaults.push_strategy,
					start_defaults.try_push_opts,
					start_defaults.wait_timeout_ms,
					{
						browser_autostart = false, -- browser is (re)opened explicitly below
						browser_cmd = browser_defaults.browser_cmd or browser_defaults.resolved_browser_cmd,
						browser_args = browser_defaults.browser_args,
					},
					arg_path
				)
			end

			-- re-open the preview surface for the current buffer
			if require("mdview.config").defaults.open_preview_tab then
				require("mdview.adapter.preview_tab").open(vim.api.nvim_get_current_buf())
			else
				require("mdview").open()
			end
			return
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

		-- allow optional file argument: prefer the parsed file_arg when provided
		local initial_target = nil
		if file_arg and file_arg ~= "" then
			local norm = normalize.path(file_arg)
			initial_target = (norm and norm ~= "") and norm or file_arg
		end

		-- Ensure server proc spawned (cwd_arg, if given, overrides mdview.config.defaults.server_cwd for this spawn)
		local proc = state.ensure_proc_started(cwd_arg)
		if not proc then
			notify("[mdview] failed to start server process", vim.log.levels.ERROR)
			return
		end
		-- Wire session + autocmds BEFORE marking the server as "running":
		-- if autocmds.attach() errors, we don't want state.get_server() left
		-- truthy (which would make every later :MDViewStart say "already
		-- running" against a never-fully-started session).
		session.init()
		autocmds.attach()
		state.set_server(proc)
		state.set_attached(true)

		-- perform chosen initial push strategy (non-blocking)
		initial_push_async(push_strategy, try_push_opts, wait_timeout, browser_opts, initial_target)

		notify("[mdview] started", vim.log.levels.INFO)
		log.debug("usercmds.start: MDViewStart completed wiring", nil, "usercmds.start", true)
	end, {
		desc = "[mdview] Start mdview preview server and attach autocommands "
			.. "(optional file arg, optional cwd=... override)",
		nargs = "*",
		complete = "file",
	})
end

return M

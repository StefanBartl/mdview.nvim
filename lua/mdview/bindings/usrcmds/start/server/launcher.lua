---@module 'mdview.bindings.usrcmds.start.server.launcher'
--- Lightweight launcher for server autostart.
--- Uses ws_client.wait_ready as primary readiness mechanism and triggers single initial push.
--- Reviewed for a further split ("Modularisieren"): `resolve_browser_url` and
--- `has_display` are already extracted as named, independently-exported
--- locals; the remaining `M.start` is one linear spawn-then-wait-then-open
--- sequence. Kept as one file.

local runner = require("mdview.adapter.runner")
local ws_client = require("mdview.adapter.ws_client")
local live_push = require("mdview.bindings.autocmds.live_push")
local browser_adapter = require("mdview.adapter.browser")
local session = require("mdview.core.session")
local autocmds = require("mdview.bindings.autocmds")
local state = require("mdview.core.state")
local normalize = require("mdview.helper.normalize")
local log = require("mdview.helper.log")

local api = vim.api
local notify = vim.notify
local schedule = vim.schedule

local M = {}

-- Reports whether a browser could plausibly be shown: always true on
-- Windows/macOS (no DISPLAY concept there), and on Unix only when a display
-- server is actually reachable (DISPLAY for X11, WAYLAND_DISPLAY for
-- Wayland). Without this, a headless SSH session with no X forwarding would
-- silently spawn a `jobstart` for a browser that can never open a window.
---@return boolean
local function has_display()
	local is_windows = require("mdview.helper.is_windows")
	if is_windows() or vim.fn.has("mac") == 1 then
		return true
	end
	return (vim.env.DISPLAY and vim.env.DISPLAY ~= "") or (vim.env.WAYLAND_DISPLAY and vim.env.WAYLAND_DISPLAY ~= "")
end
M.has_display = has_display

-- Resolve the URL for the browser tab, including the document key and the
-- shared session token as query params: the relay server rejects any /ws
-- upgrade that doesn't present both (see native/server/main.go handleWS).
-- Prefers a client dev server URL when available, falls back to the backend
-- server (production).
---@param opts table|nil # { browser_url?: string, key?: string }
---@return string
local function resolve_browser_url(opts)
	opts = opts or {}

	-- explicit per-call override (useful for tests or external launchers)
	if type(opts.browser_url) == "string" and opts.browser_url ~= "" then
		return opts.browser_url
	end

	-- static config override (mdview.config.browser.open_url)
	local open_url = require("mdview.config.browser").defaults.open_url
	if type(open_url) == "string" and open_url ~= "" then
		return open_url
	end

	local base
	if vim.g.mdview_dev_port and vim.g.mdview_dev_port > 0 then
		base = ("http://localhost:%d/"):format(vim.g.mdview_dev_port)
	else
		local browser_defaults = require("mdview.config.browser").defaults
		if browser_defaults.dev_server_port and browser_defaults.dev_server_port > 0 then
			base = ("http://localhost:%d/"):format(browser_defaults.dev_server_port)
		else
			local server_port = require("mdview.config").defaults.server_port or 43219
			base = ("http://localhost:%d/"):format(server_port)
		end
	end

	local token = state.get_token()
	local key = opts.key
	if not key or not token then
		return base
	end
	return base .. "?key=" .. normalize.path_for_url(key) .. "&token=" .. vim.uri_encode(token)
end
M.resolve_browser_url = resolve_browser_url

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

	local cmd, args, cwd, resolve_err = require("mdview.adapter.server_args").resolve()
	if not cmd then
		notify("[mdview] " .. tostring(resolve_err), vim.log.levels.ERROR)
		return nil
	end

	local proc = runner.start_server(cmd, args, cwd)
	if not proc then
		notify("[mdview] failed to spawn server process", vim.log.levels.ERROR)
		return nil
	end

	-- attach session & autocmds after successful spawn
	session.init()
	autocmds.attach()
	state.set_attached(true)
	state.set_server(proc)

	-- Wait for server health, then perform the initial full push and open
	-- the browser (only once the server is actually reachable, so the tab
	-- doesn't load against a not-yet-ready port).
	ws_client.wait_ready(function(ok)
		if ok then
			local port = vim.g.mdview_server_port or 43219
			vim.g.mdview_server_port = port
			vim.notify("[mdview] detected server port: " .. tostring(port), 2)

			schedule(function()
				log.debug("launcher: server ready — performing initial full push", nil, "launcher", true)
				local buf = api.nvim_get_current_buf()
				local key = normalize.path(api.nvim_buf_get_name(buf))
				live_push.attach() -- ensure live_push autocmds are installed (idempotent)
				live_push.push_buffer_changes(buf)

				-- open_preview_tab replaces the browser tab with an nvim-tab
				-- preview (Treesitter mirror, no HTML/relay involved at all —
				-- see mdview.adapter.preview_tab) — the relay/WASM pipeline
				-- above still runs normally, so :MDViewOpen can still open the
				-- browser later if wanted.
				if require("mdview.config").defaults.open_preview_tab then
					require("mdview.adapter.preview_tab").open(buf)
					return
				end

				-- open browser after readiness (best-effort)
				if browser_autostart and browser_adapter and browser_adapter.open then
					local browser_defaults = require("mdview.config.browser").defaults
					if browser_defaults.require_display and not has_display() then
						notify(
							"[mdview] no display available (headless/SSH session without DISPLAY) — "
								.. "skipping browser autostart. Set browser.require_display = false to override.",
							vim.log.levels.WARN
						)
						return
					end

					local browser_url = resolve_browser_url({ browser_url = opts.browser_url, key = key })
					log.debug("Opening browser: " .. browser_url, nil, "launcher", true)

					local opts_table = {
						browser_cmd = browser_cmd,
						browser_args = browser_args,
						on_exit = function(_, code)
							log.debug(("browser exited with code %s"):format(tostring(code)), nil, "launcher", true)
							if browser_defaults.stop_on_browser_exit then
								schedule(function()
									require("mdview.bindings.usrcmds.stop").stop()
								end)
							end
						end,
					}
					local ok2, handle_or_err = pcall(browser_adapter.open, browser_url, opts_table)
					if ok2 and handle_or_err then
						state.set_browser(handle_or_err)
						log.debug("launcher: browser autostart successful", nil, "launcher", true)
					else
						notify(
							("[mdview.bindings.usrcmds] browser adapter failed: %s"):format(tostring(handle_or_err)),
							vim.log.levels.WARN
						)
					end
				end
			end)
		else
			schedule(function()
				notify(
					"[mdview.bindings.usrcmds] Server health-check failed; preview may not update automatically",
					vim.log.levels.WARN
				)
			end)
		end
	end, wait_timeout)

	return true
end

return M

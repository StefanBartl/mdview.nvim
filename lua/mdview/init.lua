---@module 'mdview.init'
-- Module entrypoint for mdview.nvim.
-- Integrates browser autostart handle storage and stop-time cleanup.

local cfg = require("mdview.config")
local browser_cfg = require("mdview.config.browser")
local runner = require("mdview.adapter.runner")
local events = require("mdview.core.events")
local session = require("mdview.core.session")
local autostart = require("mdview.usercmds.autostart")
local browser_adapter = require("mdview.adapter.browser")
local ws_client = require("mdview.adapter.ws_client")
local notify = vim.notify
local log = require("mdview.helper.log")
local normalize = require("mdview.helper.normalize")

local M = {}

M.config = cfg.defaults
M.state = {
	server = nil, -- hold runner handle
	attached = false,
	browser = nil, -- holds BrowserHandle
}

---@param opts table|nil
---@return nil
function M.setup(opts)
	opts = opts or {}
	for k, v in pairs(opts) do
		M.config[k] = v
	end

	require("mdview.config.browser").setup_and_notify() -- Resolve browser at setup time and notify user if resolution failed
	require("mdview.usercmds").setup()
	require("mdview.autocmds").setup()
end

-- Start mdview server, initialize session and attach events.
-- Side effects:
--   - attempts to start a server process via runner.start_server
--   - on success sets M.state.server to the returned process handle
--   - initializes session and attaches event handlers
--   - sets M.state.attached = true
--   - schedules autostart and may set M.state.browser if a browser handle is returned
--   - notifies the user on success or failure via notify
---@return nil
function M.start()
	if M.state.server then
		notify("[mdview] server already running", vim.log.levels.INFO)
		return
	end

	log.debug("Attempting to start mdview server...", vim.log.levels.INFO, "server", true)

	-- Start the server process
	local ok, handle_or_err = pcall(runner.start_server, M.config.server_cmd, M.config.server_args, M.config.server_cwd)
	if not ok or not handle_or_err then
		notify("[mdview] failed to start server: " .. tostring(handle_or_err), vim.log.levels.ERROR)
		log.debug("Server start failed: " .. tostring(handle_or_err), vim.log.levels.ERROR, "server", true)
		return
	end

	M.state.server = handle_or_err
	session.init()
	events.attach()
	M.state.attached = true

	-- Schedule autostart browser tab and robust initial buffer push
	vim.defer_fn(function()
		local handle = autostart.start()
		if handle then
			M.state.browser = handle
			log.debug("Autostart browser handle set", vim.log.levels.INFO, "autostart", true)
		end

		-- Push initial buffer content robustly
		local bufnr = vim.api.nvim_get_current_buf()
		local path = vim.api.nvim_buf_get_name(bufnr)
		local norm_path = normalize.path(path)
		if norm_path then
			path = norm_path
		else
			log.debug("normalized path ist nil", vim.log.levels.ERROR, "init", true)
			return
		end

		if path ~= "" then
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local markdown = table.concat(lines, "\n")

			local MAX_ATTEMPTS = 5
			local attempt = 0

			local function try_push()
				attempt = attempt + 1
				ws_client.wait_ready(function(_ok)
					if _ok then
						ws_client.send_markdown(path, markdown)
						session.store(path, lines)
						log.debug(
							string.format("Initial push stored for path: %s #lines: %d", path, #lines),
							vim.log.levels.INFO,
							"autostart",
							true
						)
					else
						if attempt < MAX_ATTEMPTS then
							log.debug(
								string.format(
									"Server not ready, retrying initial push (attempt %d/%d)...",
									attempt,
									MAX_ATTEMPTS
								),
								vim.log.levels.WARN,
								"server",
								true
							)
							vim.defer_fn(try_push, 500) -- retry after 500ms
						else
							notify(
								string.format(
									"[mdview] server not ready, initial push skipped after %d attempts",
									MAX_ATTEMPTS
								),
								vim.log.levels.WARN
							)
							log.debug(
								string.format(
									"Server health check failed, initial push skipped after %d attempts",
									MAX_ATTEMPTS
								),
								vim.log.levels.WARN,
								"server",
								true
							)
						end
					end
				end, 2000) -- wait_ready timeout per attempt: 2s
			end

			try_push()
		end
	end, 500)

	notify("[mdview] started", vim.log.levels.INFO)
	log.debug("mdview server started successfully", vim.log.levels.INFO, "server", true)
end

-- If config.browser.stop_closes_browser is true (default), attempt to close stored browser handle.
-- Side effects:
--   - detaches autocommands via events.detach()
--   - stops the running server via runner.stop_server and clears M.state.server
--   - shuts down session via session.shutdown()
--   - optionally closes stored browser handle via browser_adapter.close()
--   - notifies the user of stop/failure via vim.notify
---@param close_browser_override boolean?  # when provided, explicitly control whether to close the browser handle; if nil, use browser_cfg.defaults.stop_closes_browser
---@return nil
function M.stop(close_browser_override)
	if M.state.attached then
		events.detach()
		M.state.attached = false
	end

	if M.state.server then
		pcall(runner.stop_server, M.state.server)
		M.state.server = nil
	end

	session.shutdown()

	local should_close
	if type(close_browser_override) == "boolean" then
		should_close = close_browser_override
	else
		should_close = browser_cfg.defaults.stop_closes_browser == true
	end

	if should_close and M.state.browser then
		local ok, err = browser_adapter.close(M.state.browser)
		if not ok then
			notify(("[mdview] failed to close browser: %s"):format(tostring(err)), vim.log.levels.WARN)
		end
		M.state.browser = nil
	end

	notify("[mdview] stopped", vim.log.levels.INFO)
end

-- ADD: testfunctions
-- Expose internals for REPL/testing
M._session = session
M._runner = runner
M._events = events
M._browser_adapter = browser_adapter

return M

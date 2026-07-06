---@module 'mdview.init'
-- Module entrypoint for mdview.nvim.
-- Integrates browser autostart handle storage and stop-time cleanup.

local cfg = require("mdview.config")
local runner = require("mdview.adapter.runner")
local events = require("mdview.core.events")
local session = require("mdview.core.session")
local browser_adapter = require("mdview.adapter.browser")
local state = require("mdview.core.state")
local normalize = require("mdview.helper.normalize")

local M = {}

M.config = cfg.defaults

---@param opts table|nil supports nested overrides, e.g. { browser = { browser = "firefox" } }
---@return nil
function M.setup(opts)
	cfg.merge(opts)

	-- Resolve browser at setup time and notify user if resolution failed
	require("mdview.config.browser").setup_and_notify()
	require("mdview.bindings.usrcmds").attach()
end

--- Re-open a browser tab for the current buffer against the already-running
--- mdview-server session (does NOT start a new server — use :MDViewStart for
--- that). Pushes the current buffer's content first so the new tab has
--- something to render instead of waiting for the next edit.
---@param opts table|nil # { browser_url?: string, browser_cmd?: string, browser_args?: table }
---@return boolean ok
function M.open(opts)
	opts = opts or {}

	if not state.is_attached() or not state.get_server() then
		vim.notify("[mdview] no mdview session running — start one first with :MDViewStart", vim.log.levels.WARN)
		return false
	end

	local buf = vim.api.nvim_get_current_buf()
	local key = normalize.path(vim.api.nvim_buf_get_name(buf))
	if not key or key == "" then
		vim.notify("[mdview] current buffer has no file path to preview", vim.log.levels.WARN)
		return false
	end

	-- best-effort: seed the relay with current content so the new tab isn't empty
	pcall(require("mdview.bindings.autocmds.live_push").push_buffer_changes, buf)

	local launcher = require("mdview.bindings.usrcmds.start.server.launcher")
	local browser_url = launcher.resolve_browser_url({ browser_url = opts.browser_url, key = key })

	local browser_defaults = require("mdview.config.browser").defaults
	local browser_opts = {
		browser_cmd = opts.browser_cmd or browser_defaults.resolved_browser_cmd,
		browser_args = opts.browser_args or browser_defaults.browser_args,
		on_exit = function(_, code)
			require("mdview.helper.log").debug(
				("browser exited with code %s"):format(tostring(code)),
				nil,
				"open",
				true
			)
		end,
	}

	local ok, handle_or_err = pcall(browser_adapter.open, browser_url, browser_opts)
	if ok and handle_or_err then
		state.set_browser(handle_or_err)
		vim.notify("[mdview] opened preview: " .. browser_url, vim.log.levels.INFO)
		return true
	end

	vim.notify(("[mdview] failed to open browser: %s"):format(tostring(handle_or_err)), vim.log.levels.ERROR)
	return false
end

-- ADD: testfunctions
-- Expose internals for REPL/testing
M._session = session
M._runner = runner
M._events = events
M._browser_adapter = browser_adapter

return M

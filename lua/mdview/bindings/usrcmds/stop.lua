---@module 'mdview.bindings.usrcmds.stop'
-- Side effects:
-- If config.browser.browser_autoclose is true (default), attempt to close the
-- stored browser handle.
--   - detaches mdview's autocommands
--   - stops the running relay process and clears state.server
--   - shuts down session via session.shutdown()
--   - optionally closes stored browser handle via browser_adapter.close()
--   - notifies the user of stop/failure via vim.notify

local browser_cfg = require("mdview.config.browser")
local runner = require("mdview.adapter.runner")
local session = require("mdview.core.session")
local autocmds = require("mdview.bindings.autocmds")
local browser_adapter = require("mdview.adapter.browser")
local libusercmd = require("lib.nvim.usercmd")
local state = require("mdview.core.state")
local notify = vim.notify

local M = {}

function M.attach()
  local opts = {
		desc = "[mdview] Stop mdview preview server and detach autocommands",
		nargs = 0,
  }

	libusercmd.create("MDViewStop", function()
		M.stop(browser_cfg.defaults.browser_autoclose)
	end, opts)
end

---@param close_browser_override boolean?  # when provided, explicitly control whether to close the browser handle; if nil, use browser_cfg.defaults.browser_autoclose
---@return nil
function M.stop(close_browser_override)
  if state.is_attached() then
    pcall(autocmds.teardown)
    state.set_attached(false)
  end

	-- Ask preview tabs to close themselves BEFORE killing the relay — the
	-- signal travels over the relay, so it must still be alive. This is the
	-- only way to close a tab in the "default" browser open_mode (no process
	-- handle); in "isolated" mode the handle-based close below still applies.
	if state.get_server() then
		pcall(require("mdview.adapter.ws_client").send_close)
	end

	if state.get_server() then
		pcall(runner.stop_server, state.get_server())
		state.set_server(nil)
	end

	-- Server is gone — the next wait_ready must re-verify /health instead of
	-- short-circuiting on the cached readiness of the stopped instance.
	require("mdview.adapter.ws_client").reset_ready()

	-- Forget which room the (now-closed) tab watched, so a fresh :MDViewStart
	-- doesn't route "reuse" pushes to a stale key from the previous session.
	state.set_preview_key(nil)

	-- Drop line-diff version/basis state so the next session starts from a full
	-- snapshot instead of diffing against a dead session's content.
	require("mdview.adapter.ws_client").reset_diff_state()

	session.shutdown()

	local should_close
	if type(close_browser_override) == "boolean" then
		should_close = close_browser_override
	else
		should_close = browser_cfg.defaults.browser_autoclose == true
	end

	if should_close and state.get_browser() then
		local ok, err = browser_adapter.close(state.get_browser())
		if not ok then
			notify(("[mdview] failed to close browser: %s"):format(tostring(err)), vim.log.levels.WARN)
		end
		state.set_browser(nil)
	end

	-- Only autocommands get torn down here — user commands (:MDViewStart,
	-- :MDViewStop, :MDViewOpen, :MDViewShowWebLogs) are registered once at
	-- setup() and stay available for the whole Neovim session; tearing any
	-- of them down here previously deleted :MDViewStop and :MDViewOpen from
	-- existence the first time :MDViewStop ran (fixed — see
	-- docs/Roadmap/Roadmap.md).
	require("mdview.helper.autocmds_registry").detach_all()
	notify("[mdview] stopped", vim.log.levels.INFO)
end

return M

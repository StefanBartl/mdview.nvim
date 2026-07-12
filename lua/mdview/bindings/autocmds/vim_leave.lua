---@module 'mdview.bindings.autocmds.vim_leave'
-- VimLeavePre is a global lifecycle event, not a buffer event — it must NOT
-- be pattern-restricted to markdown files. Neovim matches an autocmd's
-- `pattern` against the current buffer's name at the moment the event
-- fires; a `pattern = defaults.ft_pattern` here previously meant the relay
-- process was only stopped if the *last-focused* buffer happened to be
-- markdown, orphaning the process whenever Neovim was quit from any other
-- buffer (confirmed and fixed — see docs/Roadmap/Roadmap.md).

local autocmds_registry = require("mdview.helper.autocmds_registry")
local nvim_create_autocmd = vim.api.nvim_create_autocmd
local state = require("mdview.core.state")

local M = {}

--- @param group integer|nil
function M.attach(group)
	local opts = {
		desc = "[mdview] Stop mdview server if running before exiting Neovim",
		callback = function()
			if state.get_proc() ~= nil then
				-- Once Neovim exits the preview is frozen (no more sync), so close
				-- the browser tab too. The close signal travels over the relay, so
				-- send it BEFORE killing the process — send_close() is a short
				-- blocking curl, which also guarantees it completes before nvim
				-- exits (an async post would be lost to the shutdown).
				pcall(require("mdview.adapter.ws_client").send_close)
				require("mdview.adapter.runner").stop_server(state.get_proc())
			end
		end,
	}
	if group then	opts.group = group end

	local id = nvim_create_autocmd("VimLeavePre", opts)
	if group then
		autocmds_registry.register(group, id)
	end
end

return M

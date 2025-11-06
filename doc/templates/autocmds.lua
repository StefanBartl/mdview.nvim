---@module 'mdview.autocmds.'
--- ADD: Annotaions

local defaults = require("mdview.config").defaults
local nvim_create_autocmd = vim.api.nvim_create_autocmd
local state = require("mdview.core.state")

local M = {}

--- ADD: Annotaions
--- @param group integer|nil
function M.attach(group)
	local opts = {
		desc = "[mdview] Stop mdview server if running before exiting Neovim",
		pattern = defaults.ft_pattern,
		callback = function()
			if state.get_proc() ~= nil then
				require("mdview.adapter.runner").stop_server(state.get_proc())
			end
		end,
	}
	if group then
		opts.group = group
	end

	nvim_create_autocmd("VimLeavePre", opts)
end

return M

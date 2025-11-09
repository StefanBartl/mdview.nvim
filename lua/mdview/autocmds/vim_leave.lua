---@module 'mdview.autocmds.vim_leave'

local runner = require("mdview.adapter.runner")
local defaults = require("mdview.config").defaults
local autocmds_registry = require("mdview.helper.autocmds_registry")
local nvim_create_autocmd = vim.api.nvim_create_autocmd

local M = {}
-- AUDIT: Neben vime_leave und bufenter auch andere autcmds id nach state?
local state = require("mdview.core.state")

--- @param group integer|nil
function M.attach(group)
	local opts = {
		desc = "[mdview] Stop mdview server if running before exiting Neovim",
		pattern = defaults.ft_pattern,
		callback = function()
			if runner.proc ~= nil then
				require("mdview.adapter.runner").stop_server(runner.proc)
			end
		end,
	}
	if group then	opts.group = group end

	local id = nvim_create_autocmd("VimLeavePre", opts)
	if group then
		state._autocmd_ids[group] = state._autocmd_ids[group] or {}
	autocmds_registry.register(group, id)
	end
end

return M

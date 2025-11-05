---@module 'mdview.autocmds'

local nvim_create_autocmd = vim.api.nvim_create_autocmd
local runner = require("mdview.adapter.runner")
local on_text_change = require("mdview.autocmds.on_text_change")

local M = {}

---@return nil
function M.setup()
	nvim_create_autocmd("VimLeavePre", {
		desc = "[mdview] Stop mdview server if running before exiting Neovim",
		callback = function()
			if runner.proc ~= nil then
				require("mdview.adapter.runner").stop_server(runner.proc)
			end
		end,
	})

	on_text_change.setup()
end

return M

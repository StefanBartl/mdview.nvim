---@module 'mdview.autocmds'

local M = {}

local nvim_create_autocmd = vim.api.nvim_create_autocmd

---@return nil
function M.setup()
	nvim_create_autocmd("VimLeavePre", {
		callback = function()
			require("mdview.adapter.runner").stop_server()
		end,
	})
end

return M

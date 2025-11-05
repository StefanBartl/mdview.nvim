---@module 'mdview.autocmds'

local nvim_create_autocmd = vim.api.nvim_create_autocmd
local runner = require("mdview.adapter.runner")

local M = {}

---@return nil
function M.setup()
	nvim_create_autocmd("VimLeavePre", {
		callback = function()
			if runner.proc ~= nil then
				require("mdview.adapter.runner").stop_server(runner.proc)
			end
		end,
	})
end

return M

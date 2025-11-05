-- FIX: Sollen nur in Markdown Buffer ausführbar/sichtbar sein -> autocmd?

---@module 'mdview.usercommands'
--- Registers mdview user commands: start, stop, open, show logs

local mdview = require("mdview")
local log = require("mdview.adapter.log")
local nvim_create_user_command = vim.api.nvim_create_user_command

local M = {}

---@return nil
function M.setup()
	nvim_create_user_command("MDViewStart", function()
		mdview.start()
	end, { desc = "[mdview] Start mdview preview server and attach autocommands" })

	nvim_create_user_command("MDViewStop", function()
		mdview.stop()
	end, { desc = "[mdview] Stop mdview preview server and detach autocommands" })

	nvim_create_user_command("MDViewOpen", function()
		mdview.open()
	end, { desc = "[mdview] Open preview in browser (tries vite dev then server)" })

	nvim_create_user_command("MDViewShowLogs", function()
		log.show()
	end, { desc = "[mdview] Show mdview debug logs" })
end

return M

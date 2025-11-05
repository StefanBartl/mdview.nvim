-- FIX: Sollen nur in Markdown Buffer ausführbar/sichtbar sein -> autocmd?

---@module 'mdview.usercommands'
--- Registers mdview user commands: start, stop, open, show logs

local mdview = require("mdview")
local log = require("mdview.adapter.log")
local nvim_create_user_command = vim.api.nvim_create_user_command

local M = {}

-- Open preview in external browser
function M.mdview_open()
	local port = require("mdview.config").defaults.server_port or vim.g.mdview_server_port or 43219
	local server_url = "http://localhost:" .. tostring(port)
	local vite_url = "http://localhost:43220/"

	local function open_url(url)
		if vim.fn.has("win32") == 1 then
			vim.fn.jobstart({ "cmd", "/c", "start", "", url })
		elseif vim.fn.has("mac") == 1 then
			vim.fn.jobstart({ "open", url })
		else
			vim.fn.jobstart({ "xdg-open", url })
		end
	end

	-- Probe vite dev first
	local ok = (vim.fn.systemlist("curl -sS -I " .. vite_url .. " | head -n 1 2>/dev/null") ~= "")
	if ok then
		open_url(vite_url)
	else
		open_url(server_url)
	end
end

---@return nil
function M.setup()
	nvim_create_user_command("MDViewStart", function()
		mdview.start()
	end, { desc = "[mdview] Start mdview preview server and attach autocommands" })

	nvim_create_user_command("MDViewStop", function()
		mdview.stop()
	end, { desc = "[mdview] Stop mdview preview server and detach autocommands" })

	nvim_create_user_command("MDViewOpen", function()
		M.mdview_open()
	end, { desc = "[mdview] Open preview in browser (tries vite dev then server)" })

	nvim_create_user_command("MDViewShowLogs", function()
		log.show()
	end, { desc = "[mdview] Show mdview debug logs" })
end

return M

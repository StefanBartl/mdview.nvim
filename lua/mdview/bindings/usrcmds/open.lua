---@module 'mdview.bindings.usrcmds.open'
-- Re-opens a browser tab for the current buffer against the already-running
-- mdview session. See mdview.open() in lua/mdview/init.lua.

local mdview = require("mdview")
local usercmds_registry = require("mdview.helper.usercmds_registry")

local M = {}

function M.attach()
	local opts = {
		desc = "[mdview] Re-open the browser preview for the current buffer (session must already be running via :MDViewStart)",
		nargs = 0,
	}

	usercmds_registry.register("MDViewOpen", function()
		local ok, err = pcall(mdview.open)
		if not ok then
			vim.notify(("[mdview] :MDViewOpen failed: %s"):format(tostring(err)), vim.log.levels.ERROR)
		end
	end, opts)
end

return M

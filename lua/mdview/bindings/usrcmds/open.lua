---@module 'mdview.bindings.usrcmds.open'
-- Re-opens a browser tab for the current buffer against the already-running
-- mdview session. See mdview.open() in lua/mdview/init.lua.

local mdview = require("mdview")
local libusercmd = require("lib.nvim.usercmd")

local M = {}

function M.attach()
	local opts = {
		desc = "[mdview] Re-open the browser preview for the current buffer (session must already be running via :MDViewStart)",
		nargs = 0,
	}

	libusercmd.create("MDViewOpen", function()
		mdview.open()
	end, opts)
end

return M

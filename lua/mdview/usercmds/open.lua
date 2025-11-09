---@module 'mdview.usercmds.open'
-- ADD: Annotaions

-- FIX; NOCH KEINE IMPLEMENTATUIN

local mdview = require("mdview")
local usercmds_registry = require("mdview.helper.usercmds_registry")

local M = {}

--- ADD: Annotations
function M.attach()

	local opts = {
		desc = "[mdview] Open preview in browser (tries vite dev then server)",
		nargs = 0,
	}

	usercmds_registry.register("MDViewOpen", function()
		pcall(mdview.open)
	end, opts)
end

return M

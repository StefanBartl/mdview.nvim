---@module 'mdview.bindings.usrcmds.preview_tab'
-- Registers :MDViewPreviewTab — toggles an nvim-tab Markdown preview (no
-- browser, no relay server) for the current buffer. See
-- mdview.adapter.preview_tab for the actual implementation.

local libusercmd = require("lib.nvim.usercmd")
local preview_tab = require("mdview.adapter.preview_tab")

local M = {}

function M.attach()
	libusercmd.create("MDViewPreviewTab", function()
		preview_tab.toggle()
	end, {
		desc = "[mdview] Toggle an nvim-tab Markdown preview for the current buffer (no browser/relay)",
		nargs = 0,
	})
end

return M

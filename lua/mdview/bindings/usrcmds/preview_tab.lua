---@module 'mdview.bindings.usrcmds.preview_tab'
-- Action behind :MDView preview-tab — toggles an nvim-tab Markdown preview (no
-- browser, no relay server) for the current buffer. See
-- mdview.adapter.preview_tab for the actual implementation.

local preview_tab = require("mdview.adapter.preview_tab")

local M = {}

function M.run()
	preview_tab.toggle()
end

return M

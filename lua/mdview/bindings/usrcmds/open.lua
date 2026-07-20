---@module 'mdview.bindings.usrcmds.open'
-- Re-opens a browser tab for the current buffer against the already-running
-- mdview session. See mdview.open() in lua/mdview/init.lua. Action behind
-- :MDView open (session must already be running via :MDView start).

local mdview = require("mdview")

local M = {}

function M.run()
	mdview.open()
end

return M

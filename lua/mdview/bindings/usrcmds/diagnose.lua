---@module 'mdview.bindings.usrcmds.diagnose'
-- Action behind :MDView diagnose [path] — writes a full diagnostics report to
-- a file and opens it, so the state of every component can be handed off for
-- debugging.

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@param path string|nil
function M.run(path)
	local report = require("mdview.diagnostics").run(path)
	notify("[mdview] diagnostics written to " .. report, vim.log.levels.INFO)
	-- open it so the user sees it immediately and can copy/hand it over
	pcall(vim.cmd, "tabnew " .. vim.fn.fnameescape(report))
end

return M

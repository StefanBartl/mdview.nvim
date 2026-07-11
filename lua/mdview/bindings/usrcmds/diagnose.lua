---@module 'mdview.bindings.usrcmds.diagnose'
-- Registers :MDViewDiagnose — writes a full diagnostics report to a file and
-- opens it, so the state of every component can be handed off for debugging.

local libusercmd = require("lib.nvim.usercmd")

local M = {}

function M.attach()
	libusercmd.create("MDViewDiagnose", function(cmdopts)
		local path = cmdopts.args and cmdopts.args ~= "" and cmdopts.args or nil
		local report = require("mdview.diagnostics").run(path)
		vim.notify("[mdview] diagnostics written to " .. report, vim.log.levels.INFO)
		-- open it so the user sees it immediately and can copy/hand it over
		pcall(vim.cmd, "tabnew " .. vim.fn.fnameescape(report))
	end, {
		desc = "[mdview] Write a full diagnostics report to a file (optional path arg)",
		nargs = "?",
		complete = "file",
	})
end

return M

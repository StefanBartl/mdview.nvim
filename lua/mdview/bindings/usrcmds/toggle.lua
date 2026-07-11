---@module 'mdview.bindings.usrcmds.toggle'
-- Registers :MDViewToggle — start the preview if no relay session is running,
-- otherwise stop it. A thin dispatcher over the existing :MDViewStart /
-- :MDViewStop commands so all their arg-parsing and lifecycle guards are
-- reused unchanged; this command adds no independent start/stop logic.

local libusercmd = require("lib.nvim.usercmd")
local state = require("mdview.core.state")

local M = {}

function M.attach()
	libusercmd.create("MDViewToggle", function(cmdopts)
		if state.get_server() then
			-- A session is live — stop it. Any start-style args are irrelevant
			-- when stopping, so they're ignored (mirrors :MDViewStop, nargs=0).
			vim.cmd("MDViewStop")
			return
		end
		-- No session — start one, forwarding any file/cwd args verbatim so
		-- `:MDViewToggle file.md cwd=...` behaves exactly like :MDViewStart.
		local args = cmdopts.args and cmdopts.args ~= "" and (" " .. cmdopts.args) or ""
		vim.cmd("MDViewStart" .. args)
	end, {
		desc = "[mdview] Toggle the preview session on/off (start if stopped, stop if running)",
		nargs = "*",
		complete = "file",
	})
end

return M

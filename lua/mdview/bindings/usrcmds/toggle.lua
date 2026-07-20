---@module 'mdview.bindings.usrcmds.toggle'
-- Action behind :MDView toggle [file] [cwd=...] — start the preview if no
-- relay session is running, otherwise stop it. A thin dispatcher calling the
-- start/stop actions directly so their arg-parsing and lifecycle guards are
-- reused unchanged; this adds no independent start/stop logic of its own.

local state = require("mdview.core.state")
local start = require("mdview.bindings.usrcmds.start")
local stop = require("mdview.bindings.usrcmds.stop")

local M = {}

--- @param fargs string[]  # tokens after the "toggle" subcommand (same shape start.run expects)
function M.run(fargs)
	if state.get_server() then
		-- A session is live — stop it. Any start-style args are irrelevant
		-- when stopping, so they're ignored (mirrors :MDView stop).
		stop.run()
		return
	end
	-- No session — start one, forwarding any file/cwd args verbatim so
	-- `:MDView toggle file.md cwd=...` behaves exactly like :MDView start.
	start.run(fargs)
end

return M

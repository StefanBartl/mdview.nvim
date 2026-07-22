---@module 'mdview.bindings.usrcmds.sync'
-- Action behind :MDView sync [pause|resume|toggle] — pause/resume the
-- nvim->browser scroll sync at runtime. While paused, cursor moves in Neovim no
-- longer scroll the preview or move its cursor marker, so you can jump to a
-- reference spot without dragging a viewer along. No argument reports the state.

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@type string[]
M.actions = { "pause", "resume", "toggle" }

---@param action string|nil
---@return nil
function M.run(action)
	local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")
	action = action and vim.trim(action):lower() or ""

	if action == "" then
		notify(
			("[mdview] scroll sync is %s"):format(scroll_sync.is_paused() and "paused" or "active"),
			vim.log.levels.INFO
		)
		return
	end

	local paused
	if action == "pause" then
		scroll_sync.set_paused(true)
		paused = true
	elseif action == "resume" then
		scroll_sync.set_paused(false)
		paused = false
	elseif action == "toggle" then
		paused = scroll_sync.toggle_paused()
	else
		notify(
			("[mdview] sync: expected one of: %s"):format(table.concat(M.actions, ", ")),
			vim.log.levels.WARN
		)
		return
	end

	-- Tell the open tab so it can show/hide a "sync paused" badge — a passive
	-- viewer during a screen share then sees that the preview is intentionally
	-- frozen (you're looking something up in Neovim) rather than stuck. Live
	-- control update; a no-op when no session/tab is running.
	require("mdview.adapter.control").send({ sync = paused and "paused" or "active" })

	notify("[mdview] scroll sync " .. (paused and "paused" or "resumed"), vim.log.levels.INFO)
end

return M

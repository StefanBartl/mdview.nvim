---@module 'mdview.bindings.usrcmds.blanklines'
-- Action behind :MDView blanklines [on|off|toggle] — toggle whether runs of
-- consecutive blank lines render as visible vertical space (the
-- browser.preserve_blank_lines render option) at runtime.
--
-- Sets browser.preserve_blank_lines in the shared config (so a reopened tab
-- keeps it via ?blanklines=) and, if a session is running, pushes a live control
-- update so the open tab re-renders with the new setting without a reload.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@type string[]
M.actions = { "on", "off", "toggle" }

--- Turn blank-line preservation on/off/toggle. No argument toggles.
---@param action string|nil
---@return nil
function M.run(action)
	local browser = require("mdview.config.browser").defaults
	local cur = browser.preserve_blank_lines == true

	action = action and vim.trim(action):lower() or ""
	local on
	if action == "on" then
		on = true
	elseif action == "off" then
		on = false
	elseif action == "toggle" or action == "" then
		on = not cur
	else
		notify(
			("[mdview] blanklines: expected one of: %s"):format(table.concat(M.actions, ", ")),
			vim.log.levels.WARN
		)
		return
	end

	browser.preserve_blank_lines = on

	local label = on and "on" or "off"
	if state.get_server() and control.send({ blanklines = on }) then
		notify("[mdview] preserve blank lines: " .. label, vim.log.levels.INFO)
	else
		notify(
			("[mdview] preserve blank lines: %s (applies on next :MDView start)"):format(label),
			vim.log.levels.INFO
		)
	end
end

return M

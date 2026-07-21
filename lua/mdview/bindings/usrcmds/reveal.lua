---@module 'mdview.bindings.usrcmds.reveal'
-- Action behind :MDView reveal [on|off|toggle] — reveal/hide all private blocks
-- (```private, rendered blurred by default) in the preview at once. Purely a
-- live preview action (no persistent config): pushes a control update so the
-- open tab toggles the blur without a reload. Individual blocks can also be
-- revealed by clicking them in the browser.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

-- Best-effort mirror of the reveal state so `toggle` has something to flip.
-- Reset conservatively: a freshly opened tab starts hidden, so this may lag by
-- one toggle after a re-open, but explicit on/off always work.
M._revealed = false

---@type string[]
M.actions = { "on", "off", "toggle" }

---@param action string|nil
---@return nil
function M.run(action)
	if not state.get_server() then
		notify("[mdview] no preview session running", vim.log.levels.WARN)
		return
	end

	action = action and vim.trim(action):lower() or ""
	local reveal
	if action == "on" then
		reveal = true
	elseif action == "off" then
		reveal = false
	elseif action == "toggle" or action == "" then
		reveal = not M._revealed
	else
		notify(
			("[mdview] reveal: expected one of: %s"):format(table.concat(M.actions, ", ")),
			vim.log.levels.WARN
		)
		return
	end

	if control.send({ reveal = reveal }) then
		M._revealed = reveal
		notify("[mdview] private blocks " .. (reveal and "revealed" or "hidden"), vim.log.levels.INFO)
	else
		notify("[mdview] could not reach the preview tab", vim.log.levels.WARN)
	end
end

return M

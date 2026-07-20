---@module 'mdview.bindings.usrcmds.cursor'
-- Action behind :MDView cursor [line|caret|section|off] — switch the
-- Neovim-cursor marker mode in the preview at runtime.
--
-- Sets browser.cursor_marker in the shared config (so the next browser URL
-- carries the new ?cursor=) and, if a session is running, pushes a live control
-- update so the open tab changes immediately — no reload. Without a running
-- session it just records the choice for the next :MDView start.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local M = {}

---@type string[]
M.modes = { "line", "caret", "section", "off" }

---@param v string
---@return boolean
local function is_valid(v)
	for _, m in ipairs(M.modes) do
		if m == v then
			return true
		end
	end
	return false
end

---@param mode string|nil
---@return nil
function M.run(mode)
	local browser = require("mdview.config.browser").defaults
	mode = mode and vim.trim(mode) or ""

	if mode == "" then
		vim.notify(
			("[mdview] cursor marker: %s (choices: %s)"):format(
				tostring(browser.cursor_marker),
				table.concat(M.modes, ", ")
			),
			vim.log.levels.INFO
		)
		return
	end

	if not is_valid(mode) then
		vim.notify(
			("[mdview] unknown cursor mode %q — choose one of: %s"):format(mode, table.concat(M.modes, ", ")),
			vim.log.levels.WARN
		)
		return
	end

	---@cast mode "line"|"caret"|"section"|"off"
	browser.cursor_marker = mode

	if state.get_server() and control.send({ cursor = mode }) then
		vim.notify("[mdview] cursor marker: " .. mode, vim.log.levels.INFO)
	else
		vim.notify("[mdview] cursor marker: " .. mode .. " (applies on next :MDView start)", vim.log.levels.INFO)
	end
end

return M

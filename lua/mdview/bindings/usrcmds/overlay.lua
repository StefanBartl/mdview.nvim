---@module 'mdview.bindings.usrcmds.overlay'
-- Actions behind :MDView overlay <name> [on|off|toggle] and :MDView overlay list
-- — the single entry point for the preview's overlay system (floating TOC, …).
--
-- Sets browser.overlays[name] in the shared config (so the next browser URL
-- carries the new ?overlays=) and, if a session is running, pushes a live
-- control update so the open tab mounts/unmounts the overlay without a reload.
--
-- M.known is the Neovim-side manifest: the overlay names the client registers
-- (src/client/render/overlays/index.ts). Keep the two in sync when adding one.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@class mdview.OverlaySpec
---@field desc string

---@type table<string, mdview.OverlaySpec>
M.known = {
	toc = { desc = "floating outline with the current section highlighted" },
}

--- Registered overlay names, sorted (drives completion).
---@return string[]
function M.names()
	local out = {}
	for name in pairs(M.known) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

---@return table<string, boolean>
local function overlay_state()
	local browser = require("mdview.config.browser").defaults
	if type(browser.overlays) ~= "table" then
		browser.overlays = {}
	end
	return browser.overlays
end

--- Report every known overlay and whether it is on.
---@return nil
function M.list()
	local states = overlay_state()
	local lines = {}
	for _, name in ipairs(M.names()) do
		lines[#lines + 1] = ("  %-10s %s   — %s"):format(
			name,
			states[name] == true and "on " or "off",
			M.known[name].desc
		)
	end
	notify("[mdview] overlays:\n" .. table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Turn overlay `name` on/off/toggle. No name (or "list") reports the list.
---@param name string|nil
---@param action string|nil # on | off | toggle (default toggle)
---@return nil
function M.run(name, action)
	name = name and vim.trim(name):lower() or ""
	if name == "" or name == "list" then
		M.list()
		return
	end

	if not M.known[name] then
		notify(
			("[mdview] unknown overlay %q — known: %s"):format(name, table.concat(M.names(), ", ")),
			vim.log.levels.WARN
		)
		return
	end

	local states = overlay_state()
	action = action and vim.trim(action):lower() or "toggle"
	local on
	if action == "on" then
		on = true
	elseif action == "off" then
		on = false
	elseif action == "toggle" then
		on = states[name] ~= true
	else
		notify("[mdview] overlay: expected on | off | toggle", vim.log.levels.WARN)
		return
	end

	states[name] = on

	if state.get_server() and control.send({ overlay = { name = name, on = on } }) then
		notify(("[mdview] overlay %s: %s"):format(name, on and "on" or "off"), vim.log.levels.INFO)
	else
		notify(
			("[mdview] overlay %s: %s (applies on next :MDView start)"):format(name, on and "on" or "off"),
			vim.log.levels.INFO
		)
	end
end

return M

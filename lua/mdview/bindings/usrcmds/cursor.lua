---@module 'mdview.bindings.usrcmds.cursor'
-- Registers :MDViewCursor [line|caret|off] — switch the Neovim-cursor marker
-- mode in the preview at runtime, analogous to :MDViewTheme.
--
-- Sets browser.cursor_marker in the shared config (so the next browser URL
-- carries the new ?cursor=) and, if a session is running, pushes a live control
-- update so the open tab changes immediately — no reload. Without a running
-- session it just records the choice for the next :MDViewStart.

local libusercmd = require("lib.nvim.usercmd")
local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local M = {}

---@type string[]
M.modes = { "line", "caret", "off" }

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

function M.attach()
	libusercmd.create("MDViewCursor", function(cmdopts)
		local browser = require("mdview.config.browser").defaults
		local mode = cmdopts.args and vim.trim(cmdopts.args) or ""

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

		browser.cursor_marker = mode

		if state.get_server() and control.send({ cursor = mode }) then
			vim.notify("[mdview] cursor marker: " .. mode, vim.log.levels.INFO)
		else
			vim.notify("[mdview] cursor marker: " .. mode .. " (applies on next :MDViewStart)", vim.log.levels.INFO)
		end
	end, {
		desc = "[mdview] Set the Neovim-cursor marker in the preview (line | caret | off)",
		nargs = "?",
		complete = function(arglead)
			local out = {}
			for _, m in ipairs(M.modes) do
				if m:find(arglead, 1, true) == 1 then
					out[#out + 1] = m
				end
			end
			return out
		end,
	})
end

return M

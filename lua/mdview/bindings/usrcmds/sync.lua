---@module 'mdview.bindings.usrcmds.sync'
-- Registers :MDViewSync [pause|resume|toggle] — pause/resume the nvim->browser
-- scroll sync at runtime. While paused, cursor moves in Neovim no longer scroll
-- the preview or move its cursor marker, so you can jump to a reference spot
-- without dragging a viewer along. No argument reports the current state.

local libusercmd = require("lib.nvim.usercmd")

local M = {}

---@type string[]
M.actions = { "pause", "resume", "toggle" }

function M.attach()
	libusercmd.create("MDViewSync", function(cmdopts)
		local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")
		local action = cmdopts.args and vim.trim(cmdopts.args):lower() or ""

		if action == "" then
			vim.notify(
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
			vim.notify(
				("[mdview] MDViewSync: expected one of: %s"):format(table.concat(M.actions, ", ")),
				vim.log.levels.WARN
			)
			return
		end

		vim.notify("[mdview] scroll sync " .. (paused and "paused" or "resumed"), vim.log.levels.INFO)
	end, {
		desc = "[mdview] Pause/resume the nvim->browser scroll sync (pause | resume | toggle)",
		nargs = "?",
		complete = function(arglead)
			local out = {}
			for _, a in ipairs(M.actions) do
				if a:find(arglead, 1, true) == 1 then
					out[#out + 1] = a
				end
			end
			return out
		end,
	})
end

return M

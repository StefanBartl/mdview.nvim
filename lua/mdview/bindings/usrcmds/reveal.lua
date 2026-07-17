---@module 'mdview.bindings.usrcmds.reveal'
-- Registers :MDViewReveal [on|off|toggle] — reveal/hide all private blocks
-- (```private, rendered blurred by default) in the preview at once. Purely a
-- live preview action (no persistent config): pushes a control update so the
-- open tab toggles the blur without a reload. Individual blocks can also be
-- revealed by clicking them in the browser.

local libusercmd = require("lib.nvim.usercmd")
local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local M = {}

-- Best-effort mirror of the reveal state so `toggle` has something to flip.
-- Reset conservatively: a freshly opened tab starts hidden, so this may lag by
-- one toggle after a re-open, but explicit on/off always work.
M._revealed = false

---@type string[]
M.actions = { "on", "off", "toggle" }

function M.attach()
	libusercmd.create("MDViewReveal", function(cmdopts)
		if not state.get_server() then
			vim.notify("[mdview] no preview session running", vim.log.levels.WARN)
			return
		end

		local action = cmdopts.args and vim.trim(cmdopts.args):lower() or "toggle"
		local reveal
		if action == "on" then
			reveal = true
		elseif action == "off" then
			reveal = false
		elseif action == "toggle" or action == "" then
			reveal = not M._revealed
		else
			vim.notify(
				("[mdview] MDViewReveal: expected one of: %s"):format(table.concat(M.actions, ", ")),
				vim.log.levels.WARN
			)
			return
		end

		if control.send({ reveal = reveal }) then
			M._revealed = reveal
			vim.notify("[mdview] private blocks " .. (reveal and "revealed" or "hidden"), vim.log.levels.INFO)
		else
			vim.notify("[mdview] could not reach the preview tab", vim.log.levels.WARN)
		end
	end, {
		desc = "[mdview] Reveal/hide all private (```private) blocks in the preview (on | off | toggle)",
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

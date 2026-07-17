---@module 'mdview.bindings.usrcmds.zoom'
-- Registers :MDViewZoom [+|-|reset|<factor>] — adjust the preview font-size zoom
-- at runtime. Video calls downsample the shared screen, so bumping the preview
-- font improves legibility for the viewer without zooming the whole window.
--
-- Sets browser.zoom in the shared config (so a reopened tab starts at the same
-- zoom via ?zoom=) and, if a session is running, pushes a live control update so
-- the open tab rescales immediately.

local libusercmd = require("lib.nvim.usercmd")
local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local M = {}

local STEP = 0.1
local MIN = 0.5
local MAX = 3.0

---@param z number
---@return number
local function clamp(z)
	if z < MIN then
		return MIN
	elseif z > MAX then
		return MAX
	end
	-- round to 2 decimals so repeated +/- stays clean (0.1 steps)
	return math.floor(z * 100 + 0.5) / 100
end

function M.attach()
	libusercmd.create("MDViewZoom", function(cmdopts)
		local browser = require("mdview.config.browser").defaults
		local cur = type(browser.zoom) == "number" and browser.zoom or 1.0
		local arg = cmdopts.args and vim.trim(cmdopts.args) or ""

		if arg == "" then
			vim.notify(("[mdview] preview zoom: %d%%"):format(math.floor(cur * 100 + 0.5)), vim.log.levels.INFO)
			return
		end

		local next_zoom
		if arg == "+" or arg == "in" then
			next_zoom = clamp(cur + STEP)
		elseif arg == "-" or arg == "out" then
			next_zoom = clamp(cur - STEP)
		elseif arg == "reset" or arg == "=" then
			next_zoom = 1.0
		else
			local n = tonumber(arg)
			if not n then
				vim.notify("[mdview] MDViewZoom: expected +, -, reset, or a number", vim.log.levels.WARN)
				return
			end
			-- accept either a factor (1.5) or a percentage (150)
			next_zoom = clamp(n > 5 and n / 100 or n)
		end

		browser.zoom = next_zoom

		local label = ("%d%%"):format(math.floor(next_zoom * 100 + 0.5))
		if state.get_server() and control.send({ zoom = next_zoom }) then
			vim.notify("[mdview] preview zoom: " .. label, vim.log.levels.INFO)
		else
			vim.notify("[mdview] preview zoom: " .. label .. " (applies on next :MDViewStart)", vim.log.levels.INFO)
		end
	end, {
		desc = "[mdview] Adjust the preview font-size zoom (+ | - | reset | <factor>)",
		nargs = "?",
		complete = function(arglead)
			local out = {}
			for _, a in ipairs({ "+", "-", "reset" }) do
				if a:find(arglead, 1, true) == 1 then
					out[#out + 1] = a
				end
			end
			return out
		end,
	})
end

return M

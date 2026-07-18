---@module 'mdview.bindings.usrcmds.file_log'
-- Registers :MDViewFileLog — toggles mdview's *persistent* log file (the relay
-- stdout capture in mdview.adapter.log) at runtime.
--
-- File logging is opt-in and off by default (config `file_log`), so a plain
-- :MDViewStart never writes anything to disk. When enabled, output goes to
-- `file_log_path` — by default `stdpath("log")/mdview/relay-<timestamp>.log`,
-- never a `logs/` directory in the current working directory.
--
-- Usage:
--   :MDViewFileLog          toggle, then report the state
--   :MDViewFileLog on|off   set explicitly
--   :MDViewFileLog status   report without changing anything

local libusercmd = require("lib.nvim.usercmd")

local M = {}

---@param enabled boolean
---@param path string
local function report(enabled, path)
	if enabled then
		vim.notify("[mdview] file logging ON -> " .. path, vim.log.levels.INFO)
	else
		vim.notify("[mdview] file logging OFF", vim.log.levels.INFO)
	end
end

function M.attach()
	libusercmd.create("MDViewFileLog", function(cmdopts)
		local log = require("mdview.adapter.log")
		local sub = ((cmdopts.fargs or {})[1] or ""):lower()

		if sub == "on" or sub == "enable" then
			report(log.set_file_log(true))
		elseif sub == "off" or sub == "disable" then
			report(log.set_file_log(false))
		elseif sub == "status" then
			report(log.file_log_state())
		elseif sub == "" or sub == "toggle" then
			report(log.toggle_file_log())
		else
			vim.notify("[mdview] :MDViewFileLog expects on|off|toggle|status", vim.log.levels.WARN)
		end
	end, {
		desc = "[mdview] Toggle persistent file logging (on|off|toggle|status)",
		nargs = "?",
		complete = function(arglead)
			local out = {}
			for _, c in ipairs({ "on", "off", "toggle", "status" }) do
				if c:find(arglead, 1, true) == 1 then
					out[#out + 1] = c
				end
			end
			return out
		end,
	})
end

return M

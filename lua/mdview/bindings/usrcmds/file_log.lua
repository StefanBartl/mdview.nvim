---@module 'mdview.bindings.usrcmds.file_log'
-- Registers :MDViewFileLog — toggles mdview's *persistent* log file (the relay
-- stdout capture in mdview.adapter.log) at runtime, and points it at a path.
--
-- File logging is opt-in and off by default (config `file_log`), so a plain
-- :MDViewStart never writes anything to disk. When enabled, output goes to
-- `file_log_path` — by default `stdpath("log")/mdview/relay-<timestamp>.log`,
-- never a `logs/` directory in the current working directory.
--
-- Usage:
--   :MDViewFileLog                 toggle, then report the state
--   :MDViewFileLog on|off          set explicitly
--   :MDViewFileLog on <path>       enable and write to <path>
--   :MDViewFileLog path <path>     set the path (leaves on/off untouched)
--   :MDViewFileLog path default    fall back to config / the built-in default
--   :MDViewFileLog status          report without changing anything

local libusercmd = require("lib.nvim.usercmd")

local M = {}

---@param enabled boolean
---@param path string
local function report(enabled, path)
	if enabled then
		vim.notify("[mdview] file logging ON -> " .. path, vim.log.levels.INFO)
	else
		vim.notify("[mdview] file logging OFF (path: " .. path .. ")", vim.log.levels.INFO)
	end
end

-- Expand `~` and resolve relative paths to absolute *here*, where vim.fn.* is
-- safe — mdview.adapter.log reads the path from the relay's stdout callback (a
-- fast event context) and can't expand it itself. Resolving also means a
-- relative path is pinned to the cwd at the time the command ran, rather than
-- silently following later :cd's.
---@param path string
---@return string
local function absolute(path)
	return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
end

function M.attach()
	libusercmd.create("MDViewFileLog", function(cmdopts)
		local log = require("mdview.adapter.log")
		local args = cmdopts.fargs or {}
		local sub = (args[1] or ""):lower()
		local arg = args[2]

		if sub == "on" or sub == "enable" then
			if arg and arg ~= "" then
				log.set_file_log_path(absolute(arg))
			end
			report(log.set_file_log(true))
		elseif sub == "off" or sub == "disable" then
			report(log.set_file_log(false))
		elseif sub == "path" then
			if not arg or arg == "" then
				local _, current = log.file_log_state()
				vim.notify("[mdview] file log path: " .. current, vim.log.levels.INFO)
			elseif arg == "default" then
				report(log.set_file_log_path(nil))
			else
				report(log.set_file_log_path(absolute(arg)))
			end
		elseif sub == "status" then
			report(log.file_log_state())
		elseif sub == "" or sub == "toggle" then
			report(log.toggle_file_log())
		else
			vim.notify("[mdview] :MDViewFileLog expects on|off|toggle|status|path [<path>]", vim.log.levels.WARN)
		end
	end, {
		desc = "[mdview] Toggle persistent file logging / set its path (on|off|toggle|status|path)",
		nargs = "*",
		complete = function(arglead, cmdline)
			-- Second argument of `on`/`path` is a filename -> complete files.
			if cmdline:match("^%s*%S+%s+%S+%s") then
				return vim.fn.getcompletion(arglead, "file")
			end
			local out = {}
			for _, c in ipairs({ "on", "off", "toggle", "status", "path" }) do
				if c:find(arglead, 1, true) == 1 then
					out[#out + 1] = c
				end
			end
			return out
		end,
	})
end

return M

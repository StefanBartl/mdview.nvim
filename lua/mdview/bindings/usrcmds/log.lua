---@module 'mdview.bindings.usrcmds.log'
-- Registers :MDViewLog — shows mdview's internal structured log ring
-- (mdview.log, built on lib.nvim.logger) in a scratch buffer, with optional
-- level filtering and file export. Complements :MDViewShowWebLogs, which shows
-- the *relay's* stdout (including [client] browser diagnostics); this shows the
-- *plugin's* own log (launcher, live-push, ws_client, …).
--
-- Usage:
--   :MDViewLog                 show the whole ring
--   :MDViewLog warn            show only WARN and above (trace|debug|info|warn|error)
--   :MDViewLog export [path]   write the ring to a file (default: stdpath log)

local libusercmd = require("lib.nvim.usercmd")

local M = {}

local LEVELS = { trace = 0, debug = 1, info = 2, warn = 3, error = 4 }

-- Format the ring (optionally filtered to level >= min_level) into lines.
---@param min_level integer|nil
---@return string[]
local function format_ring(min_level)
	local ring = require("mdview.log").snapshot()
	local lines = {}
	for _, rec in ipairs(ring) do
		if type(rec) == "table" then
			local lvl = rec.level or 2
			if not min_level or lvl >= min_level then
				lines[#lines + 1] = ("%s  %-5s  %s"):format(
					tostring(rec.iso or ""),
					tostring(rec.level_name or "?"),
					tostring(rec.msg or "")
				)
			end
		end
	end
	if #lines == 0 then
		lines[1] = "(no log records" .. (min_level and " at that level" or "") .. ")"
	end
	return lines
end

---@param lines string[]
local function show_in_scratch(lines)
	vim.cmd("botright new")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_set_name(buf, "mdview://log")
end

function M.attach()
	libusercmd.create("MDViewLog", function(cmdopts)
		local args = cmdopts.fargs or {}
		local sub = (args[1] or ""):lower()

		if sub == "export" then
			local path = args[2]
			if not path or path == "" then
				local dir = vim.fn.stdpath("log")
				pcall(vim.fn.mkdir, dir, "p")
				path = dir .. "/mdview-log.txt"
			end
			local f = io.open(path, "w")
			if f then
				f:write(table.concat(format_ring(nil), "\n") .. "\n")
				f:close()
				vim.notify("[mdview] log written to " .. path, vim.log.levels.INFO)
			else
				vim.notify("[mdview] failed to write log to " .. path, vim.log.levels.ERROR)
			end
			return
		end

		local min_level = LEVELS[sub] -- nil when no/unknown filter -> show all
		show_in_scratch(format_ring(min_level))
	end, {
		desc = "[mdview] Show the internal log ring (optional level filter, or `export [path]`)",
		nargs = "*",
		complete = function(arglead)
			local cands = { "trace", "debug", "info", "warn", "error", "export" }
			local out = {}
			for _, c in ipairs(cands) do
				if c:find(arglead, 1, true) == 1 then
					out[#out + 1] = c
				end
			end
			return out
		end,
	})
end

return M

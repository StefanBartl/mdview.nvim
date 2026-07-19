---@module 'mdview.bindings.usrcmds.log'
-- Action behind :MDView log — shows mdview's internal structured log ring
-- (mdview.log, built on lib.nvim.logger) in a scratch buffer, with optional
-- level filtering and file export. Complements :MDView weblogs, which shows
-- the *relay's* stdout (including [client] browser diagnostics); this shows the
-- *plugin's* own log (launcher, live-push, ws_client, …).
--
-- Usage:
--   :MDView log                       show the whole ring
--   :MDView log warn                  show only WARN and above (trace|debug|info|warn|error)
--   :MDView log export [path]         write the ring to a file (default: stdpath log)

local M = {}

M.LEVELS = { trace = 0, debug = 1, info = 2, warn = 3, error = 4 }

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

local SCRATCH_NAME = "mdview://log"

-- Reuse the single dedicated log-view buffer across repeat invocations rather
-- than creating a new one each time — nvim_buf_set_name throws E95 on a name
-- collision, which happens whenever the previous log window is still open (its
-- bufhidden = "wipe" only fires once the buffer is no longer displayed).
---@param lines string[]
local function show_in_scratch(lines)
	local existing = vim.fn.bufnr(SCRATCH_NAME)
	if existing ~= -1 then
		local win = vim.fn.bufwinid(existing)
		if win == -1 then
			vim.cmd("botright new")
			vim.api.nvim_win_set_buf(0, existing)
		else
			vim.api.nvim_set_current_win(win)
		end
		vim.bo[existing].modifiable = true
		vim.api.nvim_buf_set_lines(existing, 0, -1, false, lines)
		vim.bo[existing].modifiable = false
		return
	end

	vim.cmd("botright new")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_set_name(buf, SCRATCH_NAME)
end

--- Show the ring, optionally filtered to `min_level` and above.
---@param min_level integer|nil
function M.show_ring(min_level)
	show_in_scratch(format_ring(min_level))
end

--- Write the whole (unfiltered) ring to a file.
---@param path string|nil  # default: stdpath("log") .. "/mdview-log.txt"
function M.export_ring(path)
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
end

return M

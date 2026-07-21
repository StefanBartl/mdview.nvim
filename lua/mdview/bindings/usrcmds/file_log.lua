---@module 'mdview.bindings.usrcmds.file_log'
-- Action behind :MDView file-log — toggles mdview's *persistent* log file (the
-- relay stdout capture in mdview.adapter.log) at runtime, and points it at a
-- path.
--
-- File logging is opt-in and off by default (config `file_log`), so a plain
-- :MDView start never writes anything to disk. When enabled, output goes to
-- `file_log_path` — by default `stdpath("log")/mdview/relay-<timestamp>.log`,
-- never a `logs/` directory in the current working directory.
--
-- Usage:
--   :MDView file-log                 toggle, then report the state
--   :MDView file-log on|off          set explicitly
--   :MDView file-log on <path>       enable and write to <path>
--   :MDView file-log path <path>     set the path (leaves on/off untouched)
--   :MDView file-log path default    fall back to config / the built-in default
--   :MDView file-log status          report without changing anything

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@param enabled boolean
---@param path string
local function report(enabled, path)
	if enabled then
		notify("[mdview] file logging ON -> " .. path, vim.log.levels.INFO)
	else
		notify("[mdview] file logging OFF (path: " .. path .. ")", vim.log.levels.INFO)
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

--- :MDView file-log on [path]
---@param path string|nil
function M.on(path)
	local log = require("mdview.adapter.log")
	if path and path ~= "" then
		log.set_file_log_path(absolute(path))
	end
	report(log.set_file_log(true))
end

--- :MDView file-log off
function M.off()
	report(require("mdview.adapter.log").set_file_log(false))
end

--- :MDView file-log toggle (also the bare :MDView file-log default)
function M.toggle()
	report(require("mdview.adapter.log").toggle_file_log())
end

--- :MDView file-log status
function M.status()
	report(require("mdview.adapter.log").file_log_state())
end

--- :MDView file-log path [value]  — `value` is a path, "default", or omitted.
---@param value string|nil
function M.path(value)
	local log = require("mdview.adapter.log")
	if not value or value == "" then
		local _, current = log.file_log_state()
		notify("[mdview] file log path: " .. current, vim.log.levels.INFO)
	elseif value == "default" then
		report(log.set_file_log_path(nil))
	else
		report(log.set_file_log_path(absolute(value)))
	end
end

return M

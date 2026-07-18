---@module 'mdview.adapter.log'
-- Collects logs for mdview server and optionally writes to a scratch buffer or file.
-- Minimal changes: replace deprecated buffer option APIs with nvim_set_option_value,
-- keep behavior and surface stable.

local api = vim.api
local schedule = vim.schedule
local echo = api.nvim_echo
local set_option_value = api.nvim_set_option_value

local M = {}

-- required config to read debug flag
local cfg = require("mdview.config")

-- ANSI/control-sequence stripping delegates to lib.nvim (mdview.nvim already
-- hard-depends on it), which was upgraded from this exact gsub chain to
-- carry the improvement upstream (lib.nvim commit 156e597) rather than keep
-- a private duplicate.
local strip_ansi = require("lib.lua.strings").strip_ansi

-- Read live rather than caching a snapshot at require-time: this module is
-- required before require('mdview').setup(opts) runs (via adapter.runner),
-- so a cached snapshot would permanently miss any user override of
-- `debug`/`log_buffer_name`. M.setup() below still allows an explicit
-- manual override that takes precedence over the main config.
---@type boolean|nil
local debug_override = nil
---@type string|nil
local buf_name_override = nil

---@return boolean
local function is_debug()
	if debug_override ~= nil then
		return debug_override
	end
	return cfg.defaults.debug == true
end

---@return string
local function log_buf_name()
	return buf_name_override or cfg.defaults.log_buffer_name or "mdview://logs"
end

---@type string[]
local log_lines = {}

-- generate a timestamped log file path
-- %Y: year, %m: month, %d: day, %H: hour, %M: minute, %S: second
local timestamp = os.date("%Y%m%d-%H%M%S")
M.LOG_BUF_NAME = string.format("./logs/debug-%s.log", timestamp)

-- Persistent file logging is OPT-IN (cfg.defaults.file_log, default false).
-- It used to default to "./logs/debuglog", which silently created a `logs/`
-- directory in whatever the cwd happened to be as soon as a preview started.
-- Both the enabled flag and the path can be overridden here via M.setup(),
-- and toggled at runtime through M.set_file_log()/:MDViewFileLog.
---@type boolean|nil
local file_log_override = nil
---@type string|nil
local file_path_override = nil
-- Resolved eagerly at require-time: file_path() is reached from M.append(),
-- which runs in the relay's stdout callback (a fast event context where
-- vim.fn.* raises E5560).
---@type string
local default_file_path = ("%s/mdview/relay-%s.log"):format(vim.fn.stdpath("log"), timestamp)

---@return boolean
local function is_file_log()
	if file_log_override ~= nil then
		return file_log_override
	end
	return cfg.defaults.file_log == true
end

-- Path used when file logging is on. Never relative to the cwd: falls back to
-- Neovim's own log dir so enabling it can't litter a project directory.
---@return string
local function file_path()
	if file_path_override then
		return file_path_override
	end
	if cfg.defaults.file_log_path then
		return cfg.defaults.file_log_path
	end
	return default_file_path
end

--- Effective file-logging state, for :MDViewFileLog and diagnostics.
---@return boolean enabled, string path
function M.file_log_state()
	return is_file_log(), file_path()
end

--- Enable/disable persistent file logging at runtime (overrides config).
---@param enabled boolean
---@return boolean enabled, string path
function M.set_file_log(enabled)
	file_log_override = enabled and true or false
	return is_file_log(), file_path()
end

--- Point persistent file logging at `path` (overrides `file_log_path`), or
--- pass nil to fall back to the config / built-in default again.
---
--- The path is stored as given: expanding `~`/relative paths needs vim.fn.*,
--- which file_path()'s caller (M.append, a fast event context) can't do — so
--- callers such as :MDViewFileLog expand before handing the path over.
---@param path string|nil
---@return boolean enabled, string path
function M.set_file_log_path(path)
	file_path_override = (path ~= "" and path) or nil
	return is_file_log(), file_path()
end

--- Flip persistent file logging.
---@return boolean enabled, string path
function M.toggle_file_log()
	return M.set_file_log(not is_file_log())
end

-- Configure the logger using an options table. Explicit overrides here take
-- precedence over mdview.config.defaults.debug / .log_buffer_name / .file_log.
---@param opts table|nil
function M.setup(opts)
	opts = opts or {}
	if opts.debug ~= nil then
		debug_override = opts.debug
	end
	if opts.buf_name then
		buf_name_override = opts.buf_name
	end
	if opts.file_log ~= nil then
		file_log_override = opts.file_log
	end
	if opts.file_path then
		file_path_override = opts.file_path
	end
end

-- Helper: return dirname of a path, works with both '/' and '\'
-- English comments:
-- Use pattern matching to avoid calling vim.fn.fnamemodify or vim.fn.expand.
---@param path string
---@return string dirname
local function path_dirname(path)
	if not path or path == "" then
		return ""
	end
	-- normalize separators to '/'
	local p = tostring(path):gsub("\\", "/")
	-- remove trailing slash
	p = p:gsub("/+$", "")
	-- find last slash
	local dir = p:match("^(.*)/")
	if not dir then
		return ""
	end
	return dir
end

-- Helper: ensure directory exists by creating missing segments using luv (vim.loop)
-- English comments:
-- Avoid calling vim.fn.mkdir to prevent E5560 in fast event contexts.
---@param dir string
---@return boolean ok, string|nil err
local function ensure_dir(dir)
	if not dir or dir == "" then
		return false, "empty directory"
	end
			---@diagnostic disable-next-line LSP-problems with uv.loop
	local stat = vim.loop.fs_stat(dir)
	if stat then
		-- already exists
		return true, nil
	end

	-- collect parts and create recursively
	local parts = {}
	for part in dir:gmatch("[^/]+") do
		parts[#parts + 1] = part
	end

	-- handle absolute path or Windows drive letter
	local prefix = ""
	-- unix absolute
	if dir:sub(1, 1) == "/" then
		prefix = "/"
	end
	-- windows drive (e.g. "C:/path")
	local drive = dir:match("^([A-Za-z]:)")
	if drive then
		prefix = drive .. "/"
		-- remove drive component from parts if present
		if parts[1] and parts[1]:lower():match("^%a:$") then
			table.remove(parts, 1)
		end
	end

	local cur = prefix
	for i = 1, #parts do
		if cur == "" then
			cur = parts[i]
		else
			cur = cur .. parts[i]
		end
		-- make sure path separators are present
		if i < #parts then
			cur = cur .. "/"
		end
			---@diagnostic disable-next-line  LSP-Problems with uuv.loop
		local st = vim.loop.fs_stat(cur)
		if not st then
			---@diagnostic disable-next-line  LSP_Problems with uv.loop
			local ok, _ = pcall(vim.loop.fs_mkdir, cur, tonumber("755", 8))
			if not ok then
				-- fs_mkdir may return nil and set errno; attempt non-pcall call for message
			---@diagnostic disable-next-line  lsp problemsuuv.loop
				local _, e = vim.loop.fs_mkdir(cur, tonumber("755", 8))
				return false, e
			end
		end
	end
	return true, nil
end

--- Read-only view of the captured relay stdout lines (includes [client] lines).
---@return string[]
function M.lines()
	local out = {}
	for i = 1, #log_lines do
		out[i] = log_lines[i]
	end
	return out
end

-- Append a line to the in-memory log store and optionally to a file.
-- Strips common ANSI escape sequences and splits on line breaks.
---@param line string
---@param prefix string? # optional prefix to prepend to each line
---@return nil
function M.append(line, prefix)
	if not line then
		return
	end
	if prefix then
		line = prefix .. " " .. line
	end

	-- strip ANSI escape sequences
	line = strip_ansi(line)

	for l in line:gmatch("([^\n\r]+)") do
		-- append to sequential table to avoid reallocations
		log_lines[#log_lines + 1] = l

		-- maintain cap of recent lines (ring behaviour by dropping oldest)
		if #log_lines > 2000 then
			table.remove(log_lines, 1)
		end

		if is_debug() then
			-- schedule UI echo to avoid calling UI functions in IO/fast callback directly
			schedule(function()
				echo({ { l, nil } }, true, {})
			end)
		end

		-- append to persistent file (opt-in, see cfg.defaults.file_log)
		if is_file_log() then
			local log_file_path = file_path()
			-- derive directory without vim.fn calls
			local log_dir = path_dirname(log_file_path)
			if log_dir and log_dir ~= "" then
				-- ensure directory exists using luv
				local ok, err = ensure_dir(log_dir)
				if not ok and is_debug() then
					schedule(function()
						echo({ { ("[mdview.log] failed to create dir %s: %s"):format(tostring(log_dir), tostring(err)), "ErrorMsg" } }, true, { err = true })
					end)
				end
			end

			-- open and write to file using Lua io (safe)
			local fd, err = io.open(log_file_path, "a")
			if fd then
				fd:write(l .. "\n")
				fd:close()
			else
				if is_debug() then
					schedule(function()
						echo({
							{
								("[mdview.log] failed to write to %s: %s"):format(tostring(log_file_path), tostring(err)),
								"ErrorMsg",
							},
						}, true, { err = true })
					end)
				end
			end
		end
	end
end

-- Show the log buffer in the current window, creating it if necessary.
---@return nil
function M.show()
	schedule(function()
		local buf = nil

		for _, b in ipairs(api.nvim_list_bufs()) do
			if api.nvim_buf_is_valid(b) and api.nvim_buf_get_name(b) == log_buf_name() then
				buf = b
				break
			end
		end

		if not buf then
			buf = api.nvim_create_buf(false, true)
			api.nvim_buf_set_name(buf, log_buf_name())

			set_option_value("buftype", "nofile", { scope = "local", buf = buf })
			set_option_value("bufhidden", "wipe", { scope = "local", buf = buf })
			-- keep buffer unlisted by default
			set_option_value("buflisted", false, { scope = "local", buf = buf })
		end

		set_option_value("modifiable", true, { scope = "local", buf = buf })
		api.nvim_buf_set_lines(buf, 0, -1, false, log_lines)
		set_option_value("modifiable", false, { scope = "local", buf = buf })

		api.nvim_set_current_buf(buf)
	end)
end

return M

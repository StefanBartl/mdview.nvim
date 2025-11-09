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
local cfg_ok, mdview_config = pcall(require, "mdview.config")

---@type boolean
local DEBUG = (cfg_ok and mdview_config and mdview_config.defaults and mdview_config.defaults.debug) or false

---@type string
local LOG_BUF_NAME = (cfg_ok and mdview_config and mdview_config.defaults and mdview_config.defaults.log_buffer_name)
	or "mdview://logs"

---@type string[]
local log_lines = {}

-- generate a timestamped log file path
-- %Y: year, %m: month, %d: day, %H: hour, %M: minute, %S: second
local timestamp = os.date("%Y%m%d-%H%M%S")
M.LOG_BUF_NAME = string.format("./logs/debug-%s.log", timestamp)

---@type string|nil
local log_file_path = "./logs/debuglog" -- optional file path for persistent logs

-- Configure the logger using an options table.
---@param opts table|nil
function M.setup(opts)
	-- English comments:
	-- Configure DEBUG, LOG_BUF_NAME and persistent file path via opts.
	opts = opts or {}
	DEBUG = opts.debug or false
	LOG_BUF_NAME = opts.buf_name or M.LOG_BUF_NAME
	log_file_path = opts.file_path
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

	-- strip ANSI escape sequences (basic set)
	line = line:gsub("%z", ""):gsub("\27%[[%d;]*m", ""):gsub("\27%]%d+;.-\7", ""):gsub("\27%[?%d+;?%d*%p?", "")

	for l in line:gmatch("([^\n\r]+)") do
		-- append to sequential table to avoid reallocations
		log_lines[#log_lines + 1] = l

		-- maintain cap of recent lines (ring behaviour by dropping oldest)
		if #log_lines > 2000 then
			table.remove(log_lines, 1)
		end

		if DEBUG then
			-- schedule UI echo to avoid calling UI functions in IO/fast callback directly
			schedule(function()
				echo({ { l, nil } }, true, {})
			end)
		end

		-- append to persistent file (if configured)
		if log_file_path then
			-- derive directory without vim.fn calls
			local log_dir = path_dirname(log_file_path)
			if log_dir and log_dir ~= "" then
				-- ensure directory exists using luv
				local ok, err = ensure_dir(log_dir)
				if not ok and DEBUG then
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
				if DEBUG then
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
			if api.nvim_buf_is_valid(b) and api.nvim_buf_get_name(b) == LOG_BUF_NAME then
				buf = b
				break
			end
		end

		if not buf then
			buf = api.nvim_create_buf(false, true)
			api.nvim_buf_set_name(buf, LOG_BUF_NAME)

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

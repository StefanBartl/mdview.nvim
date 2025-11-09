---@module 'mdview.adapter.runner'
-- Runner that spawns the local preview server process and captures output.

-- undefined fields on vim.loop; suppress those specific diagnostics for clarity.
---@diagnostic disable: undefined-field, deprecated, undefined-global, unused-local, return-type-mismatch

local api = vim.api
local uv = vim.loop
local notify = vim.notify
local buf_set_option = api.nvim_buf_set_option
local normalize = require("mdview.helper.normalize")
local state = require("mdview.core.state")
local log = require("mdview.adapter.log")

local M = {}

-- Detect Windows OS in a robust way (uv.os_uname may be nil in some environments)
---@return string|boolean
local function is_windows()
	local ok, uname = pcall(uv.os_uname)
	if not ok or not uname or not uname.version then
		return false
	end
	return tostring(uname.version):match("Windows") and true or false
end

-- Map common command names to their Windows equivalents where appropriate.
-- Example: "npm" -> "npm.cmd" on Windows so uv.spawn can execute the file directly.
---@param cmd string
---@return string|nil
local function get_exec(cmd)
	if not cmd then
		return nil
	end
	if is_windows() and cmd == "npm" then
		return "npm.cmd"
	end
	return cmd
end

-- small path join helper (forward slashes are fine on Windows with luv)
---@param ... string  # one or more path segments to join
---@return string # concatenated path using forward slashes
local function path_join(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = select(i, ...)
	end
	return table.concat(parts, "/")
end

-- check file existence using luv
---@param path string  # file or directory path to check
---@return boolean  # true if the path exists, false otherwise
local function file_exists(path)
	local normalized = normalize.path(path)
	return uv.fs_stat(normalized) ~= nil
end

-- project root detector used for reasonable default cwd
---@return string|nil  # returns the detected project root path or nil if none found
local function detect_project_root()
	-- DEVONLY: Remove REPOS_DIR in production
	-- 1) REPOS_DIR if set and contains mdview repo
	local repos_dir = vim.env.REPOS_DIR
	if repos_dir and repos_dir ~= "" then
		local candidates = { path_join(repos_dir, "mdview.nvim"), path_join(repos_dir, "mdview") }
		for _, cand in ipairs(candidates) do
			if
				file_exists(path_join(cand, "package.json"))
				or file_exists(path_join(cand, "lua", "mdview", "health.lua"))
			then
				return cand
			end
		end
	end

	-- 2) git root
	local ok, handle = pcall(io.popen, "git rev-parse --show-toplevel 2>nul")
	if ok and handle then
		local out = handle:read("*a")
		pcall(handle.close, handle)
		out = out and out:gsub("%s+$", "") or ""
		if out ~= "" and file_exists(path_join(out, "package.json")) then
			return out
		end
	end

	-- 3) cwd if it contains package.json
	local cwd = vim.fn.getcwd()
	if file_exists(path_join(cwd, "package.json")) then
		return cwd
	end

	return nil
end

-- Resolve spawn cwd precedence:
-- 1) explicit argument -> 2) config.server_cwd -> 3) project detection -> 4) current working dir
---@param optional_cwd string|nil  # optional working directory override
---@return string # resolved path to use as cwd for spawning processes
local function resolve_spawn_cwd(optional_cwd)
	if optional_cwd and optional_cwd ~= "" then
		return optional_cwd
	end
	if cfg_ok and mdview_config and mdview_config.defaults and mdview_config.defaults.server_cwd then
		return mdview_config.defaults.server_cwd
	end
	local root = detect_project_root()
	if root then
		return root
	end
	return vim.fn.getcwd()
end

-- Start the server process in a cross-platform way.
-- Ensures stdout/stderr pipes are created and spawn arguments are set.
-- Performs a pre-check for package.json when running npm scripts to provide
--  a clearer error message instead of long npm stack traces.
---@param cmd string # Command to execute (e.g., "npm" or "node")
---@param args string[]|nil # Optional array of arguments to pass to the command
---@param cwd string|nil # Optional working directory override for the spawned process
---@return SpawnedProcess|nil # Returns a process handle table on success, nil on failure
function M.start_server(cmd, args, cwd)
	args = args or {}
	if state.get_proc() and state.get_proc().handle and not state.get_proc().handle:is_closing() then
		return M.proc
	end

	local spawn_cmd = get_exec(cmd)
	local spawn_args = args

	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)

	local spawn_cwd = resolve_spawn_cwd(cwd)

	-- if run npm scripts, ensure package.json is present
	if spawn_cmd and (spawn_cmd:match("npm") or spawn_cmd == "npm.cmd") then
		if not file_exists(path_join(spawn_cwd, "package.json")) then
			vim.schedule(function()
				notify(
					"[mdview.runner] npm start aborted — no package.json found in cwd: " .. tostring(spawn_cwd),
					vim.log.levels.ERROR,
					{}
				)
			end)

			pcall(stdout.close, stdout)
			pcall(stderr.close, stderr)
			return nil
		end
	end

	if type(spawn_cmd) ~= "string" then
		vim.schedule(function()
			notify("[mdview.runner] invalid spawn command: " .. tostring(cmd), vim.log.levels.ERROR, {})
		end)
		pcall(stdout.close, stdout)
		pcall(stderr.close, stderr)
		return nil
	end

	local handle, pid, err = uv.spawn(spawn_cmd, {
		args = spawn_args,
		stdio = { nil, stdout, stderr },
		cwd = spawn_cwd,
		env = nil,
	}, function(code, signal)
		if stdout then
			pcall(stdout.close, stdout)
		end
		if stderr then
			pcall(stderr.close, stderr)
		end
		if handle then
			pcall(handle.close, handle)
		end
		M.proc = nil
		vim.schedule(function()
			notify("[mdview.runner] server exited (code=" .. tostring(code) .. ")", vim.log.levels.WARN, {})
		end)
	end)

	if not handle then
		vim.schedule(function()
			notify(
				"[mdview.runner] failed to spawn server process\ncmd="
					.. tostring(spawn_cmd)
					.. "\nargs="
					.. vim.inspect(spawn_args)
					.. "\ncwd="
					.. tostring(spawn_cwd)
					.. "\nerr="
					.. tostring(err),
				vim.log.levels.ERROR,
				{}
			)
		end)
		pcall(stdout.close, stdout)
		pcall(stderr.close, stderr)
		return nil
	end

	stdout:read_start(function(read_err, data)
		if read_err then
			vim.schedule(function()
				notify("[mdview.runner] stdout error: " .. tostring(read_err), vim.log.levels.ERROR, {})
			end)
			return
		end
		if data then
			log.append(data, "[mdview.runner]")
			if DEBUG then
				vim.schedule(function()
					api.nvim_out_write(strip_ansi(tostring(data)))
				end)
			end
		end
	end)

	stderr:read_start(function(read_err, data)
		if read_err then
			vim.schedule(function()
				notify("[mdview.runner] stderr error: " .. tostring(read_err), vim.log.levels.ERROR, {})
			end)
			return
		end
		if data then
			log.append(data, "[mdview,runner][err]")
			if DEBUG then
				vim.schedule(function()
					api.nvim_err_writeln(strip_ansi(tostring(data)))
				end)
			end
		end
	end)

	M.proc = { handle = handle, pid = pid, stdout = stdout, stderr = stderr, cwd = spawn_cwd }
	return M.proc
end

--- Stop the server process; fallback to force kill
---@param proc SpawnedProcess|nil  # process handle returned by start_server
function M.stop_server(proc)
	if not proc or not proc.handle then
		return
	end

	local handle = proc.handle
	local pid = proc.pid

	pcall(function()
		if uv.kill then
			uv.kill(pid, "sigterm")
		end
	end)

	pcall(function()
		if handle and not handle:is_closing() then
			handle:close()
		end
	end)

	pcall(function()
		if proc.stdout then
			proc.stdout:close()
		end
	end)
	pcall(function()
		if proc.stderr then
			proc.stderr:close()
		end
	end)

	M.proc = nil
end

--- Returns whether server is running
---@return boolean
function M.is_running()
	return M.proc ~= nil
end

return M

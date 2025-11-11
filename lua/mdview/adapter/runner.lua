---@module 'mdview.adapter.runner'
-- Runner that spawns the local preview server process and captures output.

-- undefined fields on vim.loop; suppress those specific diagnostics for clarity.
---@diagnostic disable: undefined-field, deprecated, undefined-global, unused-local, return-type-mismatch

local api = vim.api
local uv = vim.loop
local notify = vim.notify
local buf_set_option = api.nvim_buf_set_option
local log = require("mdview.adapter.log")
local defaults = require("mdview.config").defaults
local normalize = require("mdview.helper.normalize")
local is_windows = require("mdview.helper.is_windows")
local detect_project_root = require("mdview.helper.detect_project_root")
local get_exec = require("mdview.helper.get_exec")
local path_join = require("mdview.helper.path_join")
local file_exists = require("mdview.helper.file_exists")

local M = {}

local desc_tag = "[mdview.runner] "

-- FIX: Modularize disese funktionen

-- Resolve spawn cwd precedence:
-- 1) explicit argument -> 2) config.server_cwd -> 3) project detection -> 4) current working dir
---@param optional_cwd string|nil  # optional working directory override
---@return string # resolved path to use as cwd for spawning processes
local function resolve_spawn_cwd(optional_cwd)
	if optional_cwd and optional_cwd ~= "" then
		return optional_cwd
	end
	if cfg_ok and defaults and defaults.server_cwd then
		return defaults.server_cwd
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
-- a clearer error message instead of long npm stack traces.
---@param cmd string # Command to execute (e.g., "npm" or "node")
---@param args string[]|nil # Optional array of arguments to pass to the command
---@param cwd string|nil # Optional working directory override for the spawned process
---@return SpawnedProcess|nil # Returns a process handle table on success, nil on failure
function M.start_server(cmd, args, cwd)
	args = args or {}
	local state = require("mdview.core.state")
	if state.get_proc() and state.get_proc().handle and not state.get_proc().handle:is_closing() then
		return state.get_proc()
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
					desc_tag .. "npm start aborted — no package.json found in cwd: " .. tostring(spawn_cwd),
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
			notify(desc_tag .. "invalid spawn command: " .. tostring(cmd), vim.log.levels.ERROR, {})
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
		state.set_proc(nil)
		vim.schedule(function()
			notify(desc_tag .. "server exited (code=" .. tostring(code) .. ")", vim.log.levels.WARN, {})
		end)
	end)

	if not handle then
		vim.schedule(function()
			notify(
				desc_tag .. "failed to spawn server process\ncmd="
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
				notify(desc_tag .. "stdout error: " .. tostring(read_err), vim.log.levels.ERROR, {})
			end)
			return
		end

		if not data then return	end

		log.append(data, desc_tag)

		local s = tostring(data)

		local server_port = s:match("Running on http://localhost:(%d+)")
		if server_port then
			vim.schedule(function()
				vim.g.mdview_server_port = tonumber(server_port)
				log.append(("runner: detected backend server port %d"):format(tonumber(server_port)), desc_tag)
			end)
		end

		local dev_port = s:match("Local:%s*http://localhost:(%d+)")
		if dev_port then
			vim.schedule(function()
				vim.g.mdview_dev_port = tonumber(dev_port)
				log.append(("runner: detected dev server port %d"):format(tonumber(dev_port)), desc_tag)
			end)
		end

		if DEBUG then
			vim.schedule(function()
				api.nvim_out_write(strip_ansi(s))
			end)
		end
	end)

	stderr:read_start(function(read_err, data)
		if read_err then
			vim.schedule(function()
				notify(desc_tag .. "stderr error: " .. tostring(read_err), vim.log.levels.ERROR, {})
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

	state.set_proc({ handle = handle, pid = pid, stdout = stdout, stderr = stderr, cwd = spawn_cwd })
	return state.get_proc()
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

	state.set_proc(nil)
end

return M

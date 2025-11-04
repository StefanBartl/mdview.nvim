---@module 'mdview.adapter.runner'
--- Runner that spawns the local preview server process and captures output.

-- Several luv methods are used (new_pipe, spawn, kill). Sumneko LSP may warn about
-- undefined fields on vim.loop; suppress those specific diagnostics for clarity.
---@diagnostic disable: undefined-field, deprecated, undefined-global, unused-local, return-type-mismatch

local M = {}

local uv = vim.loop
local api = vim.api
local notify = vim.notify

M.proc = nil

-- Detect Windows OS in a robust way (uv.os_uname may be nil in some environments)
local function is_windows()
  local ok, uname = pcall(uv.os_uname)
  if not ok or not uname or not uname.version then
    return false
  end
  return tostring(uname.version):match("Windows") and true or false
end

-- Map common command names to their Windows equivalents where appropriate.
-- Example: "npm" -> "npm.cmd" on Windows so uv.spawn can execute the file directly.
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
local function path_join(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts+1] = select(i, ...) end
  return table.concat(parts, "/")
end

-- check file existence using luv
local function file_exists(path)
  return uv.fs_stat(path) ~= nil
end

-- project root detector used for reasonable default cwd
local function detect_project_root()
  -- 1) REPOS_DIR if set and contains mdview repo
  local repos_dir = vim.env.REPOS_DIR
  if repos_dir and repos_dir ~= "" then
    local candidates = { path_join(repos_dir, "mdview.nvim"), path_join(repos_dir, "mdview") }
    for _, cand in ipairs(candidates) do
      if file_exists(path_join(cand, "package.json")) or file_exists(path_join(cand, "lua", "mdview", "health.lua")) then
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
local function resolve_spawn_cwd(optional_cwd)
  if optional_cwd and optional_cwd ~= "" then return optional_cwd end
  local cfg_ok, mdview_config = pcall(require, "mdview.config")
  if cfg_ok and mdview_config and mdview_config.defaults and mdview_config.defaults.server_cwd then
    return mdview_config.defaults.server_cwd
  end
  local root = detect_project_root()
  if root then return root end
  return vim.fn.getcwd()
end

--- Start the server process in a cross-platform way.
--- Ensures stdout/stderr pipes are created and spawn arguments are set.
--- Performs a pre-check for package.json when running npm scripts to provide
--- a clearer error message instead of long npm stack traces.
---@param cmd string Command (e.g., "npm" or "node")
---@param args string[]|nil Arguments array
---@param cwd string|nil Optional working directory override
---@return table|nil Process handle table on success, nil on failure
function M.start_server(cmd, args, cwd)
  args = args or {}
  if M.proc and M.proc.handle and not M.proc.handle:is_closing() then
    return M.proc
  end

  -- resolve spawn command and args
  local spawn_cmd = get_exec(cmd)
  local spawn_args = args

  -- create pipes before spawn so callbacks can close them
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  -- determine cwd to spawn in
  local spawn_cwd = resolve_spawn_cwd(cwd)

  -- if the user wants to run npm scripts, ensure package.json is present
  if spawn_cmd and (spawn_cmd:match("npm") or spawn_cmd == "npm.cmd") then
    if not file_exists(path_join(spawn_cwd, "package.json")) then
      vim.schedule(function()
        notify("mdview: npm start aborted — no package.json found in cwd: " .. tostring(spawn_cwd), vim.log.levels.ERROR, {})
      end)
      -- cleanup pipes
      pcall(stdout.close, stdout)
      pcall(stderr.close, stderr)
      return nil
    end
  end

  -- guard: spawn_cmd must be a string
  if type(spawn_cmd) ~= "string" then
    vim.schedule(function()
      notify("mdview: invalid spawn command: " .. tostring(cmd), vim.log.levels.ERROR, {})
    end)
    pcall(stdout.close, stdout)
    pcall(stderr.close, stderr)
    return nil
  end

  -- spawn process
  local handle, pid, err = uv.spawn(spawn_cmd, {
    args = spawn_args,
    stdio = { nil, stdout, stderr },
    cwd = spawn_cwd,
    -- do not pass vim.fn.environ() directly; let child inherit environment by default
    -- if explicit env is required later, convert to table { KEY = VALUE, ... }
    env = nil,
  }, function(code, signal)
    -- cleanup on exit
    if stdout then pcall(stdout.close, stdout) end
    if stderr then pcall(stderr.close, stderr) end
    if handle then pcall(handle.close, handle) end
    M.proc = nil
    vim.schedule(function()
      notify("mdview server exited (code=" .. tostring(code) .. ")", vim.log.levels.WARN, {})
    end)
  end)

  if not handle then
    -- spawn failed immediately
    vim.schedule(function()
      notify(
        "mdview: failed to spawn server process\ncmd=" .. tostring(spawn_cmd)
        .. "\nargs=" .. vim.inspect(spawn_args)
        .. "\ncwd=" .. tostring(spawn_cwd)
        .. "\nerr=" .. tostring(err),
        vim.log.levels.ERROR,
        {}
      )
    end)
    pcall(stdout.close, stdout)
    pcall(stderr.close, stderr)
    return nil
  end

  -- read stdout
  stdout:read_start(function(read_err, data)
    if read_err then
      vim.schedule(function()
        notify("mdview stdout error: " .. tostring(read_err), vim.log.levels.ERROR, {})
      end)
      return
    end
    if data then
      vim.schedule(function()
        if api.nvim_out_write then
          api.nvim_out_write("[mdview] " .. tostring(data))
        else
          print("[mdview] " .. tostring(data))
        end
      end)
    end
  end)

  -- read stderr
  stderr:read_start(function(read_err, data)
    if read_err then
      vim.schedule(function()
        notify("mdview stderr error: " .. tostring(read_err), vim.log.levels.ERROR, {})
      end)
      return
    end
    if data then
      vim.schedule(function()
        if api.nvim_err_writeln then
          api.nvim_err_writeln("[mdview][err] " .. tostring(data))
        else
          io.stderr:write("[mdview][err] " .. tostring(data) .. "\n")
        end
      end)
    end
  end)

  M.proc = { handle = handle, pid = pid, stdout = stdout, stderr = stderr, cwd = spawn_cwd }
  return M.proc
end

--- Stop the server process gracefully; fallback to force kill.
---@param proc table process handle returned by start_server
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

  pcall(function() if proc.stdout then proc.stdout:close() end end)
  pcall(function() if proc.stderr then proc.stderr:close() end end)

  M.proc = nil
end

--- Returns whether server is running
---@return boolean
function M.is_running()
  return M.proc ~= nil
end

return M

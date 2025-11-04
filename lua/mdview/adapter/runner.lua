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

--- Detect Windows OS
local is_windows = uv.os_uname().version:match("Windows")

--- Get the correct executable for cross-platform npm scripts
local function get_exec(cmd)
  if is_windows and cmd == "npm" then
    return "npm.cmd"
  end
  return cmd
end

--- Start the server process in a cross-platform way.
---@param cmd string Command (e.g., "npm")
---@param args string[]|nil Arguments (e.g., { "run", "dev:server" })
---@return table|nil Process handle
function M.start_server(cmd, args)
  args = args or {}

  if M.proc and M.proc.handle and not M.proc.handle:is_closing() then
    return M.proc
  end

  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  local spawn_cmd = get_exec(cmd)
  local spawn_args = args

  local handle, pid, err = uv.spawn(spawn_cmd, {
    args = spawn_args,
    stdio = { nil, stdout, stderr },
    cwd = vim.fn.getcwd(),
    env = vim.fn.environ(),
  }, function(code, signal)
    if stdout then pcall(stdout.close, stdout) end
    if stderr then pcall(stderr.close, stderr) end
    if handle then pcall(handle.close, handle) end
    M.proc = nil
    vim.schedule(function()
      if notify then
        notify("mdview server exited (code=" .. tostring(code) .. ")", vim.log.levels.WARN, {})
      else
        print("mdview server exited (code=" .. tostring(code) .. ")")
      end
    end)
  end)

  if not handle then
    vim.schedule(function()
      notify(
        "mdview: failed to spawn server process\ncmd=" .. tostring(spawn_cmd)
        .. "\nargs=" .. vim.inspect(spawn_args)
        .. "\ncwd=" .. vim.fn.getcwd()
        .. "\nerr=" .. tostring(err),
        vim.log.levels.ERROR,
        {}
      )
    end)
    return nil
  end

  stdout:read_start(function(err_out, data)
    if err_out then
      vim.schedule(function()
        notify("mdview stdout error: " .. tostring(err_out), vim.log.levels.ERROR, {})
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

  stderr:read_start(function(err_err, data)
    if err_err then
      vim.schedule(function()
        notify("mdview stderr error: " .. tostring(err_err), vim.log.levels.ERROR, {})
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

  M.proc = { handle = handle, pid = pid, stdout = stdout, stderr = stderr }
  return M.proc
end

--- Stop the server process gracefully
---@param proc table
function M.stop_server(proc)
  if not proc or not proc.handle then return end

  local handle, pid = proc.handle, proc.pid
  pcall(function() if uv.kill then uv.kill(pid, "sigterm") end end)
  pcall(function() if handle and not handle:is_closing() then handle:close() end end)
  pcall(function() if proc.stdout then proc.stdout:close() end end)
  pcall(function() if proc.stderr then proc.stderr:close() end end)

  M.proc = nil
end

---@return boolean
function M.is_running()
  return M.proc ~= nil
end

return M

---@module 'mdview.usercmds.autostart'
--- Autostart helper: start server and open preview. Integrates with mdview.adapter.browser when available.
--- Returns browser handle when it started a controllable browser instance, otherwise nil.

---FIX: `uv`-LSP-warns
-- undefined fields on vim.loop; suppress those specific diagnostics for clarity.
---@diagnostic disable: undefined-field, deprecated, undefined-global, unused-local, return-type-mismatch

local runner = require("mdview.adapter.runner")
local api = vim.api
local notify = vim.notify
local schedule = vim.schedule
local nvim_create_autocmd = api.nvim_create_autocmd

local M = {}
local SERVER_URL = "http://localhost:43219"

M.wait_for_ready = true -- whether to wait for server before opening preview

-- Main autostart function: starts server and opens browser/preview.
-- Returns browser handle if a controllable instance was started, otherwise nil.
-- Start/Autostart Funktion mit on-change Update
---@param wait boolean|nil whether to wait for server before sending
function M.start(wait)
  wait = (wait == nil) and M.wait_for_ready or wait

  if runner.is_running() then
    runner.stop_server(runner.proc)
  end

  runner.start_server("npm", { "run", "dev:server" })

  local handle, err = require("mdview.adapter.browser").open(SERVER_URL)
  if not handle and err then
    schedule(function()
      notify(("[mdview.usercommands] browser adapter: %s"):format(tostring(err)), vim.log.levels.WARN)
    end)
  end

  local function send_current_buffer()
    local buf = api.nvim_get_current_buf()
    local path = api.nvim_buf_get_name(buf)
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    require("mdview.adapter.ws_client").send_markdown(path, table.concat(lines, "\n"))
  end

  if wait then
    require("mdview.adapter.ws_client").wait_ready(function(ok)
      if ok then
        schedule(function()
          notify("[mdview.usercommands] Server ready, sending current buffer...", vim.log.levels.INFO)
          send_current_buffer()
        end)
      else
        schedule(function()
          notify("[mdview.usercommands] Server health-check failed, preview may not update automatically", vim.log.levels.WARN)
        end)
      end
    end)
  end

  nvim_create_autocmd({ "BufWritePost", "TextChanged", "TextChangedI" }, {
    pattern = "*.md",
    callback = send_current_buffer,
  })

  nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if handle then
        require("mdview.adapter.browser").close(handle)
      end
      if runner.is_running() then
        runner.stop_server(runner.proc)
      end
    end,
  })

  return handle
end


return M

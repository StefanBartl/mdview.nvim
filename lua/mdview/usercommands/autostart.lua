---FIX: `uv`-LSP

---@module 'mdview.usercommands.autostart'
--- Autostart helper: start server and open preview. Integrates with mdview.adapter.browser when available.
--- Returns browser handle when it started a controllable browser instance, otherwise nil.

local runner = require("mdview.adapter.runner")
local notify = vim.notify

local M = {}
local SERVER_URL = "http://localhost:43219"

-- Toggle: whether to wait for server before opening preview
M.wait_for_ready = true


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
    vim.schedule(function()
      notify(("[mdview] browser adapter: %s"):format(tostring(err)), vim.log.levels.WARN)
    end)
  end

  local function send_current_buffer()
    local buf = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    require("mdview.adapter.ws_client").send_markdown(path, table.concat(lines, "\n"))
  end

  if wait then
    require("mdview.adapter.ws_client").wait_ready(function(ok)
      if ok then
        vim.schedule(function()
          notify("[mdview] Server ready, sending current buffer...", vim.log.levels.INFO)
          send_current_buffer()
        end)
      else
        vim.schedule(function()
          notify("[mdview] Server health-check failed, preview may not update automatically", vim.log.levels.WARN)
        end)
      end
    end)
  end

  vim.api.nvim_create_autocmd({ "BufWritePost", "TextChanged", "TextChangedI" }, {
    pattern = "*.md",
    callback = send_current_buffer,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
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

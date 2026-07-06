---@module 'mdview.test.runner'
-- Test helper: start mdview server, poll health, send initial push.
-- Usage (cmd is the mdview-server binary path resolved by
-- mdview.adapter.server_args.resolve(), not a script to run under a
-- runtime — there's no Node/Go/Rust runtime dependency post-rewrite):
-- :lua require('mdview.test.runner').test_server_start("/path/to/mdview-server", {"--port", "43219", "--token", "x", "--web-root", "dist/client"})

local runner = require("mdview.adapter.runner")
local ws_client = require("mdview.adapter.ws_client")
local api = vim.api
local notify = vim.notify

local M = {}

--- Start server + test health + push current buffer
---@param cmd string
---@param args string[]|nil
function M.test_server_start(cmd, args)
  args = args or {}
  local proc = runner.start_server(cmd, args, nil)
  if not proc then
    notify("[mdview.test] server failed to start", vim.log.levels.ERROR)
    return
  end
  notify("[mdview.test] server started, waiting for health...", vim.log.levels.INFO)

  -- Poll server health
  ws_client.wait_ready(function(ok)
    if ok then
      notify("[mdview.test] server ready, sending initial buffer", vim.log.levels.INFO)
      local bufnr = api.nvim_get_current_buf()
      local path = api.nvim_buf_get_name(bufnr)
      if path ~= "" then
        local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
        ws_client.send_markdown(path, table.concat(lines, "\n"))
        notify("[mdview.test] initial push sent for " .. path, vim.log.levels.INFO)
      else
        notify("[mdview.test] current buffer has no path, skipping push", vim.log.levels.WARN)
      end
    else
      notify("[mdview.test] server health check failed", vim.log.levels.ERROR)
    end
  end, 5000)
end

return M


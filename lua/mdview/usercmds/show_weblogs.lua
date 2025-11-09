---@module 'mdview.usercmds.show_weblogs'
--- Exposes a small `attach` function to register the user command.

local api = vim.api
local log = require("mdview.adapter.log")
local nvim_create_user_command = api.nvim_create_user_command

local M = {}

--- Attach and register the MDViewShowWebLogs user command.
function M.attach()
  local opts = {
    desc = "[mdview] Show mdview debug logs from the Web-Application",
    nargs = 0,
  }

  nvim_create_user_command("MDViewShowWebLogs", function()
    pcall(log.show)
  end, opts)
end

return M





---@module 'mdview.usercmds.'
--- ADD: Annotaions

local api = vim.api
local log = require("mdview.helper.log")
local nvim_create_user_command = api.nvim_create_user_command

local M = {}

--- ADD: Annotaions
function M.attach()
  local opts = {
    desc = "[mdview] ....",
    nargs = 0,
  }

  nvim_create_user_command("MDView   ", function()
    pcall(log.show)
  end, opts)
end

return M

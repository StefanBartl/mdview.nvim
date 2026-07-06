



---@module 'mdview.bindings.usrcmds.'
--- ADD: Annotaions

local log = require("mdview.helper.log")
local libusercmd = require("lib.nvim.usercmd")

local M = {}

--- ADD: Annotaions
function M.attach()
  local opts = {
    desc = "[mdview] ....",
    nargs = 0,
  }

  libusercmd.create("MDView   ", function()
    log.show()
  end, opts)
end

return M

---@module 'mdview.bindings.usrcmds.show_weblogs'
--- Exposes a small `attach` function to register the user command.

local log = require("mdview.adapter.log")
local libusercmd = require("lib.nvim.usercmd")

local M = {}

--- Attach and register the MDViewShowWebLogs user command.
function M.attach()
  local opts = {
    desc = "[mdview] Show mdview debug logs from the Web-Application",
    nargs = 0,
  }

  libusercmd.create("MDViewShowWebLogs", function()
    log.show()
  end, opts)
end

return M

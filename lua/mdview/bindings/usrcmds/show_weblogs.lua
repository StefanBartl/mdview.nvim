---@module 'mdview.bindings.usrcmds.show_weblogs'
--- Action behind :MDView weblogs — shows mdview debug logs from the
--- Web-Application.

local log = require("mdview.adapter.log")

local M = {}

function M.run()
  log.show()
end

return M

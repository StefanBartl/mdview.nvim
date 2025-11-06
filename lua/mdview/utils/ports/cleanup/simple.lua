---@module 'mdview.utils.ports.cleanup.simple'
--- Simple wrapper to free a TCP port asynchronously (Windows + Unix).

--- Usage: port_cleanup.free_port(43219)


local port_utils = require("mdview.utils.ports.cleanup.cross_os")

local M = {}

--- Kill all processes using the given port immediately.
---@param port number TCP port to free
function M.free_port(port)
  if not port or type(port) ~= "number" then
    vim.notify("free_port: invalid port", vim.log.levels.ERROR)
    return
  end
  port_utils.kill_port_async(port)
end

M.free_port(43219)

return M

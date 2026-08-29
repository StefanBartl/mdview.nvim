---@module 'mdview.adapter.control'
-- Live preview-control updates: push small JSON control objects (cursor mode,
-- zoom factor) to the open preview tab so runtime commands (:MDViewCursor,
-- :MDViewZoom) take effect without reloading the tab. Routed to the same room
-- the tab watches — the preview key in "reuse" behavior, otherwise the current
-- buffer's path — matching live_push's target resolution.

local ws_client = require("mdview.adapter.ws_client")
local target_key = require("mdview.helper.target_key")

local M = {}

--- Send a live control update to the open preview tab.
--- No-op when no session is running or no target room can be resolved.
---@param fields table # e.g. { cursor = "caret" } or { zoom = 1.2 }
---@return boolean sent
function M.send(fields)
  if type(fields) ~= "table" or vim.tbl_isempty(fields) then
    return false
  end
  if not require("mdview.core.state").get_server() then
    return false
  end
  local key = target_key.resolve(0)
  if not key then
    return false
  end
  local ok, json = pcall(vim.json.encode, fields)
  if not ok or type(json) ~= "string" then
    return false
  end
  ws_client.send_control(key, json)
  return true
end

return M

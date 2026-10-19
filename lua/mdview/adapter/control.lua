---@module 'mdview.adapter.control'
-- Live preview-control updates: push small JSON control objects (cursor mode,
-- zoom factor) to the open preview tab so runtime commands (:MDView cursor,
-- :MDView zoom) take effect without reloading the tab. Routed to the same room
-- the tab watches — the preview key in "reuse" behavior, otherwise the current
-- buffer's path — matching live_push's target resolution.

local ws_client = require("mdview.adapter.ws_client")
local target_key = require("mdview.helper.target_key")

local M = {}

--- Send a live control update to the open preview tab.
--- No-op when no session is running or no target room can be resolved.
---@param fields table # e.g. { cursor = "caret" } or { zoom = 1.2 }
---@param room string|nil # room to send to; nil: the room of the current buffer
---@return boolean sent
function M.send(fields, room)
  if type(fields) ~= "table" or vim.tbl_isempty(fields) then
    return false
  end
  if not require("mdview.core.state").get_server() then
    return false
  end
  local key = (type(room) == "string" and room ~= "") and room or target_key.resolve(0)
  if not key then
    return false
  end
  local ok, json = pcall(vim.json.encode, fields)
  if not ok or type(json) ~= "string" then
    return false
  end
  ws_client.send_control(key, json)
  -- The tabs of other display languages follow the controls of the preview (zoom, cursor, overlays); the badge of the
  -- display language belongs to one room and is not repeated.
  if fields.displayLang == nil then
    for _, follower in ipairs(require("mdview.core.lang_rooms").followers(key)) do
      ws_client.send_control(follower, json)
    end
  end
  return true
end

--- Send a control update that concerns the editor rather than one document
--- (e.g. the cursor paragraph color after `:colorscheme`) to every open tab.
--- With `browser.behavior = "reuse"` that is the one tab, reached through
--- send()'s own routing. Otherwise every document has a tab of its own: the
--- update goes to the rooms Neovim pushed a document into this session (and to
--- the current buffer's room, should it not be among them yet), so it arrives
--- no matter which buffer is current -- also an unnamed one. Of those, only
--- the rooms the relay reports a connected tab for get it (one request per
--- tab, not per document ever edited); should the relay not answer that, all
--- of them do.
---@param fields table
---@return boolean sent # sent (or, with a tab per document, queued) to at least one room
function M.broadcast(fields)
  local behavior = require("mdview.config.browser").defaults.behavior or "reuse"
  if behavior == "reuse" then
    return M.send(fields)
  end
  if type(fields) ~= "table" or vim.tbl_isempty(fields) or not require("mdview.core.state").get_server() then
    return false
  end
  local rooms = require("mdview.bindings.autocmds.live_push").rooms()
  local current = target_key.resolve(0)
  if current and not vim.tbl_contains(rooms, current) then
    rooms[#rooms + 1] = current
  end
  if #rooms == 0 then
    return false
  end
  ws_client.tab_rooms(function(tabs)
    for _, room in ipairs(rooms) do
      if not tabs or vim.tbl_contains(tabs, room) then
        M.send(fields, room)
      end
    end
  end)
  return true
end

return M

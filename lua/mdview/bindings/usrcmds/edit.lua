---@module 'mdview.bindings.usrcmds.edit'
-- Action behind :MDView edit [on|off|toggle] — switch block editing in the
-- preview: a click on a heading, paragraph, list item, code block, table or
-- quote opens its source lines for editing, and the edit is written back to
-- the buffer (one undo step).
--
-- Off by default, because a click on text would otherwise open an editor.
-- Sets `edit_blocks` in the shared config (so the next browser URL carries
-- ?edit=1) and pushes a live control update, so an open tab switches without a
-- reload; switching off also closes an editor that is open right now.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@type string[]
M.actions = { "on", "off", "toggle" }

---@param action string|nil
---@return nil
function M.run(action)
  local cfg = require("mdview.config").defaults
  action = action and vim.trim(action):lower() or "toggle"

  local on
  if action == "on" then
    on = true
  elseif action == "off" then
    on = false
  elseif action == "toggle" or action == "" then
    on = cfg.edit_blocks ~= true
  else
    notify(("[mdview] edit: expected one of: %s"):format(table.concat(M.actions, ", ")), vim.log.levels.WARN)
    return
  end

  cfg.edit_blocks = on
  local label = on and "on (click a block in the preview)" or "off"

  if state.get_server() then
    -- The inbound poll may not have been running (nothing else needed it).
    if on then
      pcall(require("mdview.adapter.inbound_poll").start)
    end
    control.send({ editBlocks = on })
    notify("[mdview] preview editing: " .. label, vim.log.levels.INFO)
  else
    notify("[mdview] preview editing: " .. label .. " (applies on next :MDView start)", vim.log.levels.INFO)
  end
end

return M

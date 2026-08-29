---@module 'mdview.bindings.usrcmds.blanklines'
-- Action behind :MDView blanklines [on|off|toggle] — switch whether the
-- preview shows every blank line between blocks as extra vertical space, or
-- collapses runs of them to a single paragraph gap (CommonMark's own
-- behavior, and the default here).
--
-- Sets browser.preserve_blank_lines in the shared config (so the next browser
-- URL carries ?blanklines=1) and, if a session is running, pushes a live
-- control update so the open tab adds/removes the spacing without a reload.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@type string[]
M.actions = { "on", "off", "toggle" }

---@param action string|nil
---@return nil
function M.run(action)
  local browser = require("mdview.config.browser").defaults
  action = action and vim.trim(action):lower() or "toggle"

  local on
  if action == "on" then
    on = true
  elseif action == "off" then
    on = false
  elseif action == "toggle" or action == "" then
    on = browser.preserve_blank_lines ~= true
  else
    notify(("[mdview] blanklines: expected one of: %s"):format(table.concat(M.actions, ", ")), vim.log.levels.WARN)
    return
  end

  browser.preserve_blank_lines = on
  local label = on and "showing all blank lines" or "compressed (default)"

  if state.get_server() and control.send({ blankLines = on }) then
    notify("[mdview] preview blank lines: " .. label, vim.log.levels.INFO)
  else
    notify("[mdview] preview blank lines: " .. label .. " (applies on next :MDView start)", vim.log.levels.INFO)
  end
end

return M

---@module 'mdview.bindings.usrcmds.spotlight'
-- Action behind :MDView spotlight [on|off|toggle] -- switch whether
-- spotlight.nvim's highlights are mirrored into the preview.
--
-- On by default (and a no-op without spotlight.nvim); this is the switch for the
-- moment a shared screen or an open tab must not show what is marked in Neovim.
--
-- Sets browser.spotlight_sync in the shared config and, while a session runs,
-- re-reads the spotlights right away: switching on paints the ones that are
-- active now, switching off sends the relay an empty state so the highlights in
-- every open tab disappear instead of being stranded there.

local state = require("mdview.core.state")
local mirror = require("mdview.core.spotlight_mirror")

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
    on = browser.spotlight_sync == false
  else
    notify(("[mdview] spotlight: expected one of: %s"):format(table.concat(M.actions, ", ")), vim.log.levels.WARN)
    return
  end

  browser.spotlight_sync = on
  local label = on and "mirrored in the preview" or "not mirrored"
  if on and not mirror.plugin() then
    label = label .. " (spotlight.nvim not found: nothing to mirror)"
  end

  local applied = state.get_server() and true or false
  if applied then
    require("mdview.bindings.autocmds.spotlight_sync").sync_now()
    notify("[mdview] spotlight highlights: " .. label, vim.log.levels.INFO)
  else
    notify("[mdview] spotlight highlights: " .. label .. " (applies on next :MDView start)", vim.log.levels.INFO)
  end
end

return M

---@module 'mdview.bindings.usrcmds.selection'
-- Action behind :MDView selection [on|off|toggle] — switch whether the Neovim
-- visual selection is mirrored into the preview as a highlight.
--
-- Off by default, and meant to be toggled on for as long as you are showing the
-- document to someone: "this bit here is what I meant". While you are editing
-- rather than presenting, every v/V drag reaching the browser is noise — the
-- audience would watch you select things you are only operating on.
--
-- Sets browser.selection_sync in the shared config (so the next browser URL
-- carries ?sel=) and pushes a live control update: switching on prepares the
-- open tab right away (the mirror needs the renderer's source-position spans,
-- so the tab re-renders once — better now than in the middle of the first
-- thing you point at), switching off clears a highlight that is currently
-- drawn instead of stranding it there.

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
    on = browser.selection_sync ~= true
  else
    notify(("[mdview] selection: expected one of: %s"):format(table.concat(M.actions, ", ")), vim.log.levels.WARN)
    return
  end

  browser.selection_sync = on
  local label = on and "mirrored in the preview" or "not mirrored"

  local selection_sync = require("mdview.bindings.autocmds.selection_sync")
  local applied = state.get_server() and true or false
  if applied then
    selection_sync.reset()
    control.send({ selectionSync = on })
    if on then
      -- Draw the selection that is active right now, instead of waiting for
      -- the next cursor move to make the command look like it did something.
      selection_sync.send_current_selection(vim.api.nvim_get_current_buf())
    end
  end

  if applied then
    notify("[mdview] visual selection: " .. label, vim.log.levels.INFO)
  else
    notify("[mdview] visual selection: " .. label .. " (applies on next :MDView start)", vim.log.levels.INFO)
  end
end

return M

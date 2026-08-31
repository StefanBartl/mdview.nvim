---@module 'mdview.bindings.usrcmds.selection'
-- Action behind :MDView selection [on|off|toggle] — switch whether the Neovim
-- visual selection is mirrored into the preview as a highlight.
--
-- On by default. Switch it off when you are editing rather than presenting and
-- don't want every v/V drag to reach the browser tab — or when someone is
-- watching a tab you'd rather not have follow your cursor.
--
-- Sets browser.selection_sync in the shared config (so the next browser URL
-- carries ?sel=), and pushes a live control update to the open tab: switching
-- it off clears a highlight that is currently drawn instead of leaving it
-- stranded there.

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
    on = browser.selection_sync == false
  else
    notify(("[mdview] selection: expected one of: %s"):format(table.concat(M.actions, ", ")), vim.log.levels.WARN)
    return
  end

  browser.selection_sync = on
  local label = on and "mirrored in the preview" or "not mirrored"

  local selection_sync = require("mdview.bindings.autocmds.selection_sync")
  local applied = state.get_server() and true or false
  if applied then
    if on then
      -- Draw the selection that is active right now, instead of waiting for
      -- the next cursor move to make the command look like it did something.
      selection_sync.reset()
      selection_sync.send_current_selection(vim.api.nvim_get_current_buf())
    else
      selection_sync.clear()
    end
  end

  if applied then
    notify("[mdview] visual selection: " .. label, vim.log.levels.INFO)
  else
    notify("[mdview] visual selection: " .. label .. " (applies on next :MDView start)", vim.log.levels.INFO)
  end
end

return M

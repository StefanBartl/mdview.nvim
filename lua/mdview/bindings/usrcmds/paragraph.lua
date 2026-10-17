---@module 'mdview.bindings.usrcmds.paragraph'
-- Action behind :MDView paragraph [on|off|toggle] — switch the cursor paragraph
-- highlight: the preview tints the block (paragraph, list, table, code block,
-- quote, heading) the Neovim cursor is in. See mdview.core.cursor_paragraph.
--
-- Sets browser.cursor_paragraph in the shared config (so the next browser URL
-- carries ?para=) and, with a session running, pushes a live control update
-- with the current color of the MdviewCursorParagraph group, followed by a
-- position ping so the highlight appears right away instead of on the next
-- cursor move.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")
local cursor_paragraph = require("mdview.core.cursor_paragraph")

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
    on = browser.cursor_paragraph ~= true
  else
    notify(("[mdview] paragraph: expected one of: %s"):format(table.concat(M.actions, ", ")), vim.log.levels.WARN)
    return
  end

  browser.cursor_paragraph = on
  local label = on and "highlighted in the preview" or "not highlighted"

  if state.get_server() and control.send(cursor_paragraph.payload(on)) then
    if on then
      local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")
      if not scroll_sync.is_paused() then
        -- Best-effort: the tab only knows a cursor line once a ping came in.
        pcall(scroll_sync.send_current_position, vim.api.nvim_get_current_buf())
      end
    end
    notify("[mdview] cursor paragraph: " .. label, vim.log.levels.INFO)
  else
    notify("[mdview] cursor paragraph: " .. label .. " (applies on next :MDView start)", vim.log.levels.INFO)
  end
end

return M

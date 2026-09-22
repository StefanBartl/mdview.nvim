---@module 'mdview.bindings.usrcmds.cursor'
-- Action behind :MDView cursor [line|caret|section|off|toggle] — switch the
-- Neovim-cursor marker mode in the preview at runtime.
--
-- "toggle" is a shortcut for flipping "section" on/off specifically (the
-- spotlight-on-current-heading mode, the one most likely to be toggled
-- on-and-off repeatedly, e.g. while presenting): section -> off, anything
-- else -> section. For any other mode switch, name it explicitly.
--
-- Sets browser.cursor_marker in the shared config (so the next browser URL
-- carries the new ?cursor=) and, if a session is running, pushes a live control
-- update so the open tab changes immediately — no reload. Without a running
-- session it just records the choice for the next :MDView start.
--
-- Switching away from "caret" (the only mode needing inline source-position
-- spans) forces the client to re-render, and a re-render only re-places the
-- marker if it has already heard a real cursor position at least once (see
-- main.ts). Until the next CursorMoved, that leaves the new mode showing
-- nothing at all -- for "section" that means no spotlight and no dimming,
-- easy to mistake for the feature being broken. A position ping right after
-- the mode switch closes that gap instead of waiting on the user to nudge
-- the cursor.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")
local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@type string[]
M.modes = { "line", "caret", "section", "off", "toggle" }

---@internal
---@param v string
---@return boolean
local function is_valid(v)
  for _, m in ipairs(M.modes) do
    if m == v then
      return true
    end
  end
  return false
end

---@param mode string|nil
---@return nil
function M.run(mode)
  local browser = require("mdview.config.browser").defaults
  mode = mode and vim.trim(mode) or ""

  if mode == "" then
    notify(
      ("[mdview] cursor marker: %s (choices: %s)"):format(tostring(browser.cursor_marker), table.concat(M.modes, ", ")),
      vim.log.levels.INFO
    )
    return
  end

  if mode == "toggle" then
    mode = (browser.cursor_marker == "section") and "off" or "section"
  end

  if not is_valid(mode) then
    notify(
      ("[mdview] unknown cursor mode %q — choose one of: %s"):format(mode, table.concat(M.modes, ", ")),
      vim.log.levels.WARN
    )
    return
  end

  ---@cast mode "line"|"caret"|"section"|"off"
  browser.cursor_marker = mode

  if state.get_server() and control.send({ cursor = mode }) then
    if mode ~= "off" then
      -- Best-effort: paint the new marker immediately instead of leaving it
      -- blank until the cursor happens to move (see module comment above).
      pcall(scroll_sync.send_current_position, vim.api.nvim_get_current_buf())
    end
    notify("[mdview] cursor marker: " .. mode, vim.log.levels.INFO)
  else
    notify("[mdview] cursor marker: " .. mode .. " (applies on next :MDView start)", vim.log.levels.INFO)
  end
end

return M

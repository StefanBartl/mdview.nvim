---@module 'mdview.bindings.usrcmds.pin'
-- Action behind :MDView pin [on|off|toggle|status] — hold the preview on the
-- document it is showing, instead of letting it follow the active buffer.
--
-- The default `browser.behavior = "reuse"` gives you one tab that follows you:
-- switch Markdown files in Neovim and the browser switches too. While writing
-- that is what you want. While *reading* it is not — opening a second file to
-- check something takes the document you were showing off the screen, and only
-- switching back brings it there again. That is worst in the case the preview
-- exists for: presenting, where the audience watches the tab and not you.
--
-- `:MDView pin` freezes the tab on the current document. Everything that would
-- otherwise reach it from another buffer is suppressed at the source (see
-- mdview.core.pin): content pushes, scroll pings, the selection mirror, and
-- auto-opened tabs in "new_tab" behavior. The pinned document itself stays
-- fully live — edit it and the preview still updates.
--
-- `:MDView pin off` releases it and immediately catches the tab up with the
-- buffer you are actually in, rather than leaving it on the released document
-- until the next buffer switch happens to move it.

local api = vim.api
local state = require("mdview.core.state")
local pin = require("mdview.core.pin")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@type string[]
M.actions = { "on", "off", "toggle", "status" }

--- Shorten a path for a message: relative to the cwd, else under `~`.
---@internal
---@param path string
---@return string
local function short(path)
  return vim.fn.fnamemodify(path, ":~:.")
end

---@internal
---@return string
local function behavior()
  return require("mdview.config.browser").defaults.behavior or "reuse"
end

---@internal
---@return nil
local function report()
  local path = pin.get()
  if path then
    notify(("[mdview] preview is pinned to %s"):format(short(path)), vim.log.levels.INFO)
  else
    notify("[mdview] preview is not pinned — it follows the active buffer", vim.log.levels.INFO)
  end
end

--- Pin the preview to the current buffer's document.
---@internal
---@return boolean ok
local function pin_current()
  -- A pin lives and dies with the tab it holds (mdview.core.pin, cleared on
  -- stop/attach), so pinning without a session would be silently dropped by
  -- the very next :MDView start. Say so instead.
  if not state.get_server() then
    notify("[mdview] pin: no preview session running — :MDView start one first", vim.log.levels.WARN)
    return false
  end

  local buf = api.nvim_get_current_buf()
  if not require("mdview.helper.previewable").is(buf) then
    notify("[mdview] pin: the current buffer is not one mdview previews", vim.log.levels.WARN)
    return false
  end

  local path = pin.set(buf)
  if not path then
    notify("[mdview] pin: the current buffer has no file path to pin", vim.log.levels.WARN)
    return false
  end

  -- Only "reuse" follows the active buffer in the first place; under the other
  -- behaviors a pin still stops "new_tab" from spawning tabs behind you, but
  -- it is not the thing the user probably thinks they just switched off.
  local suffix = ""
  if behavior() ~= "reuse" then
    suffix = (" (browser.behavior = '%s' — the preview never followed the active buffer anyway)"):format(behavior())
  end

  notify(("[mdview] preview pinned to %s%s"):format(short(path), suffix), vim.log.levels.INFO)
  return true
end

--- Release the pin and let the preview follow the active buffer again.
---@internal
---@return boolean ok
local function unpin()
  local prev = pin.clear()
  if not prev then
    notify("[mdview] preview is not pinned — it already follows the active buffer", vim.log.levels.INFO)
    return false
  end

  -- Catch the tab up with the buffer you are in now. Without this the preview
  -- would sit on the released document until the next buffer switch, making
  -- the command look like it did nothing.
  local caught_up = false
  if state.get_server() and not require("mdview.config").defaults.open_preview_tab and behavior() == "reuse" then
    caught_up = require("mdview.bindings.autocmds.buffer_switch").resync(api.nvim_get_current_buf())
  end

  local tail = caught_up and " — showing the current buffer again" or " — following the active buffer again"
  notify(("[mdview] preview unpinned from %s%s"):format(short(prev), tail), vim.log.levels.INFO)
  return true
end

---@param action string|nil # on|off|toggle|status; nil/empty toggles
---@return nil
function M.run(action)
  action = action and vim.trim(action):lower() or ""

  if action == "status" then
    report()
    return
  end

  if action == "on" then
    pin_current()
    return
  end

  if action == "off" then
    unpin()
    return
  end

  if action == "toggle" or action == "" then
    if pin.is_pinned() then
      unpin()
    else
      pin_current()
    end
    return
  end

  notify(("[mdview] pin: expected one of: %s"):format(table.concat(M.actions, ", ")), vim.log.levels.WARN)
end

return M

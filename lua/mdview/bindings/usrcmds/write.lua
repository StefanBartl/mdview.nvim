---@module 'mdview.bindings.usrcmds.write'
-- Action behind :MDView write [on|off|toggle] — "write in the browser" mode:
-- the cursor caret (`browser.cursor_marker = "caret"`) and block editing
-- (`edit_blocks`) switched together, so editing in the preview needs one
-- command instead of `:MDView cursor caret` + `:MDView edit` (+ `:MDView start`).
--
--   * on      both on. Without a running session it starts one (exactly like
--             a plain :MDView start), with both already set, so the first
--             browser URL carries ?cursor=caret&edit=1 and the inbound poll
--             comes up with the session.
--   * off     both off: block editing off, a "caret" marker back to what it
--             was before `on` (or the configured default); any other marker
--             is left alone (the caret is already off). NEVER stops the
--             session — the preview keeps running, so the same command can
--             switch writing on again.
--   * toggle  (default) off when both are on, otherwise on — a mixed state
--             (only one of the two on) toggles to on.
--
-- While a session runs, both changes go out in ONE live control update, so the
-- open tab switches without a reload.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@type string[]
M.actions = { "on", "off", "toggle" }

--- The cursor marker that was active before `on` switched to "caret", so `off`
--- can put it back. nil: none recorded (fall back to the configured default).
---@type "line"|"block"|"section"|"off"|nil
local prev_marker = nil

--- Whether write mode is fully on (caret marker AND block editing).
---@return boolean
function M.is_on()
  local cfg = require("mdview.config").defaults
  return cfg.edit_blocks == true and cfg.browser.cursor_marker == "caret"
end

--- The marker `off` returns to: the one recorded at `on`, else the configured
--- default, else "line" — never "caret" itself (that would leave half of
--- write mode on).
---@internal
---@return "line"|"block"|"section"|"off"
local function marker_after_off()
  if prev_marker then
    return prev_marker
  end
  local default = require("mdview.config.DEFAULTS").browser.cursor_marker
  if default ~= "caret" then
    return default
  end
  return "line"
end

--- Push the current mode to a running session's open tab (one control update).
---@internal
---@param on boolean
---@param marker string
---@return nil
local function push_live(on, marker)
  if on then
    -- The inbound poll may not have been running (nothing else needed it).
    pcall(require("mdview.adapter.inbound_poll").start)
  end
  if control.send({ cursor = marker, editBlocks = on }) then
    local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")
    if marker ~= "off" and not scroll_sync.is_paused() then
      -- Paint the new marker right away instead of waiting for CursorMoved
      -- (same reason as :MDView cursor, see cursor.lua).
      pcall(scroll_sync.send_current_position, vim.api.nvim_get_current_buf())
    end
  end
end

---@param action string|nil
---@return nil
function M.run(action)
  local cfg = require("mdview.config").defaults
  local browser = cfg.browser
  action = action and vim.trim(action):lower() or "toggle"

  local on
  if action == "on" then
    on = true
  elseif action == "off" then
    on = false
  elseif action == "toggle" or action == "" then
    on = not M.is_on()
  else
    notify(("[mdview] write: expected one of: %s"):format(table.concat(M.actions, ", ")), vim.log.levels.WARN)
    return
  end

  if on then
    if browser.cursor_marker ~= "caret" then
      prev_marker = browser.cursor_marker
    end
    browser.cursor_marker = "caret"
  else
    -- Only undo the caret: a marker the user picked meanwhile (or one that
    -- was never "caret", e.g. `section` with :MDView edit on) stays as it is.
    if browser.cursor_marker == "caret" then
      browser.cursor_marker = marker_after_off()
    end
    prev_marker = nil
  end
  cfg.edit_blocks = on

  if state.get_server() then
    push_live(on, browser.cursor_marker)
    notify("[mdview] write mode: " .. (on and "on (caret + block editing)" or "off"), vim.log.levels.INFO)
    return
  end

  if on then
    -- No session: start one. The config is already set, so the preview opens
    -- with the caret and block editing on — no second command needed.
    notify("[mdview] write mode: on (caret + block editing), starting the preview", vim.log.levels.INFO)
    require("mdview.bindings.usrcmds.start").run({})
  else
    notify("[mdview] write mode: off (applies on next :MDView start)", vim.log.levels.INFO)
  end
end

--- Test seam: forget the recorded pre-`on` marker.
---@return nil
function M._reset()
  prev_marker = nil
end

return M

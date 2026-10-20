---@module 'mdview.core.cursor_blink'
-- Blinking of the block cursor marker (browser.cursor_marker = "block"). The
-- setting is `browser.cursor_blink`: false (steady, default), true (the default
-- period) or { ms = 530 }. It reaches the preview as ?blink=<ms> in the tab's
-- URL and as `cursorBlink` in a live control update. The client clamps the period
-- and never blinks under prefers-reduced-motion, whatever is set here.

local M = {}

--- Blink period used for `true` and for a table without `ms`, in ms.
M.DEFAULT_MS = 530

--- The setting as the client takes it: `false` (steady) or a period in ms.
---@param value boolean|integer|{ ms?: integer }|nil
---@return false|integer
function M.normalize(value)
  if value == true then
    return M.DEFAULT_MS
  end
  local ms = value
  if type(value) == "table" then
    ms = value.ms or M.DEFAULT_MS
  end
  if type(ms) == "number" and ms > 0 then
    return math.floor(ms + 0.5)
  end
  return false
end

--- `&blink=<ms>` for the preview URL, or "" while steady (a reopened tab then
--- starts steady, which is also what the client assumes without the parameter).
---@param browser { cursor_blink?: boolean|integer|{ ms?: integer } }
---@return string
function M.url_param(browser)
  local ms = M.normalize(browser.cursor_blink)
  if not ms then
    return ""
  end
  return "&blink=" .. ms
end

return M

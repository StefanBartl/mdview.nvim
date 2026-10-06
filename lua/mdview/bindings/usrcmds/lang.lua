---@module 'mdview.bindings.usrcmds.lang'
-- Action behind :MDView lang [<code>|off|refresh] -- show the preview in
-- another language than the buffer, or back in the buffer's own.
--
--   :MDView lang en       the buffer stays as it is, the preview shows English
--   :MDView lang off      the original again, at once
--   :MDView lang refresh  translate the current document again now (the
--                         trigger "manual" waits for exactly this)
--   :MDView lang          report the state, change nothing
--
-- Sets browser.display_lang in the shared config. A running session re-pushes
-- the current buffer so the change shows immediately; without one the choice
-- applies on the next :MDView start. The translation is done by language.nvim
-- (core/display.lua); this file only switches it.

local state = require("mdview.core.state")
local display = require("mdview.core.display")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

--- Completion candidates: the two verbs and the usual target languages. Any
--- other code the engine knows works as well when typed out.
---@type string[]
M.values = {
  "off",
  "refresh",
  "en",
  "de",
  "fr",
  "es",
  "it",
  "pt",
  "nl",
  "pl",
  "cs",
  "sv",
  "da",
  "fi",
  "no",
  "tr",
  "ru",
  "uk",
  "el",
  "hu",
  "ro",
  "ja",
  "ko",
  "zh",
}

---@internal
---@return string
local function describe()
  local lang = display.lang()
  local transform = require("mdview.config").defaults.browser.transform
  if not lang then
    local base = "[mdview] display language: off (the preview shows the buffer as it is)"
    if type(transform) == "function" then
      base = base .. "; browser.transform is set"
    end
    return base
  end
  local st = display.status()
  local parts = { ("[mdview] display language: %s, trigger %s"):format(lang, display.trigger()) }
  if display.trigger() == "idle" then
    parts[#parts + 1] = ("%d ms"):format(display.debounce_ms())
  end
  local info = display.engine_info()
  if not info.found then
    parts[#parts + 1] = "language.nvim not found: the preview stays original"
  elseif info.available then
    parts[#parts + 1] = ("engine %s"):format(info.engine or "?")
  else
    parts[#parts + 1] = ("engine unavailable (%s)"):format(info.err or "?")
  end
  local label = st.state
  if st.state == "translating" and st.done and st.total then
    label = ("translating %d/%d"):format(st.done, st.total)
  elseif st.state == "off" then
    label = "waiting for the first push"
  end
  if st.message then
    label = label .. " (" .. st.message .. ")"
  end
  parts[#parts + 1] = label
  return table.concat(parts, "; ")
end

--- Push the current buffer again so a changed setting shows at once. Only with
--- a running session and a previewable buffer; otherwise the setting waits for
--- the next push.
---@internal
---@param reason "enable"|"refresh"
---@return boolean pushed
local function repush(reason)
  if not state.get_server() then
    return false
  end
  local buf = vim.api.nvim_get_current_buf()
  require("mdview.adapter.ws_client").wait_ready(function(ok)
    if not ok or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    require("mdview.bindings.autocmds.live_push").push_buffer_changes(buf, { full = true, reason = reason })
  end)
  return true
end

---@param arg string|nil
---@return nil
function M.run(arg)
  arg = arg and vim.trim(arg) or ""
  if arg == "" then
    notify(describe(), vim.log.levels.INFO)
    return
  end

  local lowered = arg:lower()
  if lowered == "off" then
    display.set_lang(nil)
    local pushed = repush("enable")
    notify(
      "[mdview] display language: off" .. (pushed and "" or " (no running session: nothing to refresh)"),
      vim.log.levels.INFO
    )
    return
  end

  if lowered == "refresh" then
    if not display.lang() then
      notify("[mdview] display language is off: set one first, e.g. `:MDView lang en`", vim.log.levels.WARN)
      return
    end
    if not repush("refresh") then
      notify("[mdview] no running session: start one with `:MDView start`", vim.log.levels.WARN)
    end
    return
  end

  local ok, err = display.set_lang(arg)
  if not ok then
    notify(("[mdview] lang: %s (expected a language code such as en, or off)"):format(err or "?"), vim.log.levels.WARN)
    return
  end
  if not display.language() then
    notify(
      "[mdview] display language set to " .. arg .. ", but language.nvim was not found: the preview stays original",
      vim.log.levels.WARN
    )
    return
  end
  if repush("enable") then
    notify(("[mdview] display language: %s (translating the preview)"):format(arg), vim.log.levels.INFO)
  else
    notify(("[mdview] display language: %s (applies on the next :MDView start)"):format(arg), vim.log.levels.INFO)
  end
end

return M

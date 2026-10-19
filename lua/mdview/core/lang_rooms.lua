---@module 'mdview.core.lang_rooms'
--- Browser tabs that show the previewed document in a language of their own.
---
--- `browser.display_lang` is ONE language for the preview. This adds more: the buffer stays in its own language, the
--- tab that `:MDView start` opened shows it as it is (or in `display_lang`), and each tab opened with
--- `:MDView lang open <code>` shows the same document in <code> -- say the original in Neovim, one tab in Spanish and
--- one in Italian. Every buffer the preview follows is translated for each of them.
---
--- A tab like that is a room of its own on the relay: the key of the room the preview follows plus `#<code>`. The
--- relay treats a key as opaque text. What the main room gets is repeated for these rooms by the senders that address
--- a room (`ws_client`: scroll, spans; `adapter.control`: the live controls), the text itself goes through
--- `mdview.core.display` once for each language (`src.lang`), so the same document in two languages has two
--- translations, two caches and two badges, and a result of one is never shown in the tab of the other.
---
--- Read only on purpose: what a tab of this kind sends back (a checkbox, an edit) has no line of the translation to
--- land on, and the key is no document. Only available with `browser.behavior = "reuse"` (the room the preview
--- follows is one key); with a tab for each document the rooms would have to follow each of them.

local M = {}

local notify = require("lib.nvim.notify").create("").notify

--- The languages that have a tab, in the order they were opened.
---@type { code: string, key: string }[]
local rooms = {}

---@param code any
---@return boolean
function M.valid_code(code)
  return type(code) == "string" and code:match("^%a[%w_%-]*$") ~= nil and #code <= 16
end

--- The key of the room the preview follows (the tab `:MDView start` opened), or nil.
---@return string|nil
local function main_key()
  local key = require("mdview.core.state").get_preview_key()
  if type(key) == "string" and key ~= "" then
    return key
  end
  return nil
end

--- The room key of a language: the room the preview follows with `#<code>`.
---@param code string
---@param main string|nil
---@return string|nil
function M.key_for(code, main)
  main = main or main_key()
  if not main or not M.valid_code(code) then
    return nil
  end
  return main .. "#" .. code
end

--- The tabs of other languages, with their room keys.
---@return { code: string, key: string }[]
function M.list()
  return vim.deepcopy(rooms)
end

--- The room keys that repeat what is sent to `key`: those of the other languages, when `key` is the room the
--- preview follows. Empty for any other room (a lang room is not repeated into itself).
---@param key string|nil
---@return string[]
function M.followers(key)
  local out = {}
  if #rooms == 0 or type(key) ~= "string" or key == "" or key ~= main_key() then
    return out
  end
  for _, r in ipairs(rooms) do
    out[#out + 1] = r.key
  end
  return out
end

--- Whether `key` is the room of one of these tabs.
---@param key string|nil
---@return boolean
function M.is_lang_room(key)
  for _, r in ipairs(rooms) do
    if r.key == key then
      return true
    end
  end
  return false
end

--- Forget every tab (the session stopped; their rooms go with the relay).
---@return nil
function M.reset()
  rooms = {}
end

--- Register `code` and say what the tab needs; does NOT open the browser (see `open`).
---@param code string
---@return string|nil key
---@return string|nil err
function M.add(code)
  if not M.valid_code(code) then
    return nil, "not a language code: " .. tostring(code)
  end
  local behavior = require("mdview.config.browser").defaults.behavior or "reuse"
  if behavior ~= "reuse" then
    return nil, 'tabs of other languages need browser.behavior = "reuse" (the preview follows one room)'
  end
  local main = main_key()
  if not main then
    return nil, "no preview tab is open yet (:MDView start opens it)"
  end
  for _, r in ipairs(rooms) do
    if r.code == code then
      return r.key, nil
    end
  end
  local key = M.key_for(code, main)
  rooms[#rooms + 1] = { code = code, key = key }
  return key, nil
end

--- Forget the tab of `code` (or every one), cancel what is translated for it. The browser tab itself is left to the
--- person to close; it keeps what it showed.
---@param code string|nil
---@return integer removed
function M.remove(code)
  local kept, removed = {}, 0
  for _, r in ipairs(rooms) do
    if code == nil or r.code == code then
      removed = removed + 1
      pcall(function()
        require("mdview.core.display").forget_room(r.key)
      end)
    else
      kept[#kept + 1] = r
    end
  end
  rooms = kept
  return removed
end

--- Show `bufnr` in every tab of another language: the translation of the buffer for each, pushed to its room.
--- `opts.reason` is the reason of the push that is going on ("edit"|"save"|"switch"|...); `full` forces a full snapshot.
---@param bufnr integer
---@param opts { path: string, reason?: string, full?: boolean }
---@return nil
function M.push(bufnr, opts)
  if #rooms == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local main = main_key()
  local ws_client = require("mdview.adapter.ws_client")
  local live_push = require("mdview.bindings.autocmds.live_push")
  local pin = require("mdview.core.pin")
  for _, r in ipairs(rooms) do
    -- The room of a language follows the room the preview follows: a key left over from another session is not fed.
    if main and r.key == main .. "#" .. r.code then
      local first = true
      require("mdview.core.mirror").lines_async(bufnr, function(lines)
        if not vim.api.nvim_buf_is_valid(bufnr) or pin.blocks(bufnr) then
          return
        end
        ws_client.send_content(r.key, lines, { full = first and (opts.full or nil) or nil })
        if first then
          first = false
          live_push.announce_document(r.key, opts.path)
        end
      end, { target = r.key, path = opts.path, reason = opts.reason, lang = r.code })
    end
  end
end

--- Open the browser tab for `code`: registers it, seeds it with the translation of the current buffer, and opens the
--- URL of its room.
---@param code string
---@param opts { browser_url?: string }|nil
---@return boolean ok
---@return string|nil err
function M.open(code, opts)
  opts = opts or {}
  local state = require("mdview.core.state")
  if not state.is_attached() or not state.get_server() then
    return false, "no mdview session running (:MDView start)"
  end
  local key, err = M.add(code)
  if not key then
    return false, err
  end
  local buf = vim.api.nvim_get_current_buf()
  local path = require("mdview.helper.normalize").path(vim.api.nvim_buf_get_name(buf))
  if path and path ~= "" then
    -- Seed the room before the tab joins: it renders at once instead of waiting for the next edit.
    M.push(buf, { path = path, reason = "enable", full = true })
  end
  local launcher = require("mdview.bindings.usrcmds.start.server.launcher")
  local url = launcher.resolve_browser_url({ browser_url = opts.browser_url, key = key })
  local browser_defaults = require("mdview.config.browser").defaults
  local browser_opts = {
    open_mode = browser_defaults.open_mode,
    focus = browser_defaults.focus,
    browser_cmd = browser_defaults.resolved_browser_cmd,
    browser_args = browser_defaults.browser_args,
  }
  local ok, handle = pcall(require("mdview.adapter.browser").open, url, browser_opts)
  if not ok or not handle then
    return false, "failed to open the browser: " .. tostring(handle)
  end
  notify(("[mdview] tab for %q opened: %s"):format(code, url), vim.log.levels.INFO)
  return true, nil
end

return M

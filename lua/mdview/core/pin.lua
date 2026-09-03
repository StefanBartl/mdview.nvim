---@module 'mdview.core.pin'
--- Document pinning: hold the open preview on ONE document while you keep
--- moving around Neovim.
---
--- By default (`browser.behavior = "reuse"`) the single preview tab follows the
--- active buffer — switch to another Markdown file and the browser switches
--- with you. That is the right default while writing, and exactly wrong while
--- *reading*: consulting a second document (a spec, a README, notes) yanks the
--- one you were showing out of the tab, and nothing brings it back but
--- switching to it again.
---
--- A pin freezes the preview on the document that was open when you pinned it.
--- Everything that would otherwise reach that tab from another buffer — the
--- content push, the scroll ping, the selection mirror, an auto-opened tab —
--- is suppressed at the source while the pin is up, so the browser keeps
--- showing (and scrolling) the pinned document. Editing the pinned document
--- itself is unaffected; the pin blocks *other* buffers, not the preview.
---
--- Session state, like `state.preview_key`: cleared on `:MDView stop` and on a
--- fresh attach, so a pin never outlives the tab it was pinned to. Driven by
--- `:MDView pin [on|off|toggle|status]`
--- (`mdview.bindings.usrcmds.pin`).

local api = vim.api
local normalize = require("mdview.helper.normalize")

local M = {}

--- Normalized path of the pinned document, or nil when nothing is pinned.
--- Deliberately a path and not a buffer number: `:e!` / a reload / closing and
--- reopening the file all give the document a life of its own beyond one
--- bufnr, and the room key the relay uses is the path anyway.
---@type string|nil
local pinned = nil

---@internal
---@param bufnr integer|nil
---@return string|nil # normalized path, or nil when the buffer has no file
local function path_of(bufnr)
  local ok, name = pcall(api.nvim_buf_get_name, bufnr or 0)
  if not ok or name == "" then
    return nil
  end
  return normalize.path(name)
end

--- The room key the pinned document's tab is watching.
---
--- Same rule as `mdview.helper.target_key`, but anchored to the pinned
--- document rather than to whatever buffer is current: in "reuse" behavior
--- every buffer routes to the one tab's room (`state.preview_key`), so the
--- pinned document's room is that key; in "new_tab"/"manual" each document has
--- its own room, which for the pinned one is its own path.
---@return string|nil
function M.room()
  if not pinned then
    return nil
  end
  local behavior = require("mdview.config.browser").defaults.behavior or "reuse"
  if behavior == "reuse" then
    local pk = require("mdview.core.state").get_preview_key()
    if type(pk) == "string" and pk ~= "" then
      return pk
    end
  end
  return pinned
end

--- Whether outgoing traffic for `bufnr` must be dropped because the preview is
--- pinned to a different document.
---
--- Two conditions, both needed. The buffer must not BE the pinned document —
--- the pinned document's own edits, scrolls and selections are exactly what the
--- tab should keep receiving. And the traffic must actually be headed for the
--- pinned document's room: under "new_tab"/"manual" every document has its own
--- room, so a push from another buffer lands in a tab of its own and takes
--- nothing away from the pinned one. Blocking it there would turn a pin into a
--- global mute, which is not what it means.
---@param bufnr integer|nil # defaults to the current buffer
---@return boolean
function M.blocks(bufnr)
  if not pinned then
    return false
  end
  local path = path_of(bufnr)
  if path and path == pinned then
    return false
  end
  local target = require("mdview.helper.target_key").resolve(bufnr or 0)
  return target ~= nil and target == M.room()
end

--- @return boolean
function M.is_pinned()
  return pinned ~= nil
end

--- The pinned document's normalized path, or nil.
---@return string|nil
function M.get()
  return pinned
end

--- Pin the preview to `bufnr`'s document.
---@param bufnr integer|nil # defaults to the current buffer
---@return string|nil path # the pinned path, or nil when the buffer has no file
function M.set(bufnr)
  local path = path_of(bufnr)
  if not path then
    return nil
  end
  pinned = path
  return path
end

--- Release the pin. Returns the path that was pinned, for the caller's message.
---@return string|nil previous
function M.clear()
  local prev = pinned
  pinned = nil
  return prev
end

--- Move an ACTIVE pin to `bufnr`'s document; a no-op when nothing is pinned.
---
--- For the one case where the tab changes document on purpose while pinned:
--- `:MDView open` re-points the tab at the current buffer, so the pin has to
--- come along or it would go on blocking the very document now on screen.
---@param bufnr integer|nil # defaults to the current buffer
---@return string|nil path # the new pinned path, or nil if nothing moved
function M.follow(bufnr)
  if not pinned then
    return nil
  end
  return M.set(bufnr)
end

return M

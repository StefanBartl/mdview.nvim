---@module 'mdview.bindings.autocmds.selection_sync'
-- Mirrors the Neovim visual selection into the open preview: what you select
-- with v / V / CTRL-V in the buffer is highlighted in the browser, live.
--
-- Built for showing a document to other people — a lecture, a screen share, a
-- walkthrough of a checklist or README. Pointing at something in Neovim is
-- invisible to an audience looking at the browser tab; selecting it now says
-- "this part, here" in the window they are actually watching.
--
-- Rides the /control channel (small ephemeral JSON) rather than the content
-- push: a selection is a transient signal that the next one supersedes, and
-- the relay already forwards control objects to the room the tab watches.
--
-- Gated behind browser.selection_sync (default true — :MDView selection off).

local control = require("mdview.adapter.control")
local previewable = require("mdview.helper.previewable")
local defaults = require("mdview.config").defaults
local autocmd = require("lib.nvim.bindings.autocmd")
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

--- Visual modes, mapped to the three shapes the client draws. Select mode
--- (s / S / CTRL-S) is deliberately absent: it is replaced by the next
--- printable key, so mirroring it would flicker more than it informs.
---@type table<string, "char"|"line"|"block">
local VISUAL_MODES = {
  v = "char",
  V = "line",
  ["\22"] = "block", -- CTRL-V
}

--- ModeChanged patterns matching every transition INTO and OUT OF a visual
--- mode (the pattern is matched against "old_mode:new_mode"). Narrow on
--- purpose: an i->n transition must not wake this module at all.
---@type string[]
local MODE_PATTERNS = { "*:[vV\22]*", "[vV\22]*:*" }

--- Minimum gap between two selection pushes while dragging a selection. Lower
--- than the scroll-sync throttle (150 ms) because a growing selection is the
--- thing being looked at, not a side effect of it; a trailing send (see
--- on_cursor_moved) guarantees the final position always arrives.
local THROTTLE_MS = 60

local last_sent_at = 0
local trailing_scheduled = false

--- Last payload actually accepted by the transport, so an unchanged selection
--- (CursorMoved fires for moves that don't change it) costs no HTTP request.
--- "none" means "the tab has been told there is no selection".
---@type string|nil
local last_payload = nil

---@internal
---@return integer
local function now_ms()
  local uv = vim.uv or vim.loop
  return uv.now()
end

--- The current visual selection in source coordinates, or nil when no visual
--- mode is active.
---
--- Columns are 1-based **byte** columns — the same convention comrak puts into
--- the client's `data-sp` attributes, so nothing has to be converted in
--- between. `ec` addresses the first byte of the last selected character; the
--- client widens it to that character's end.
---@return { mode: "char"|"line"|"block", sl: integer, sc: integer, el: integer, ec: integer }|nil
function M.current()
  local shape = VISUAL_MODES[vim.fn.mode()]
  if not shape then
    return nil
  end

  local anchor = vim.fn.getpos("v") -- the end of the selection the cursor is not on
  local cursor = vim.fn.getpos(".")
  local sl, sc = anchor[2], anchor[3]
  local el, ec = cursor[2], cursor[3]

  -- Either end can be the earlier one (the cursor may sit at the top of the
  -- selection); the client only ever draws forwards.
  if el < sl or (el == sl and ec < sc) then
    sl, sc, el, ec = el, ec, sl, sc
  end

  if shape == "block" then
    -- A blockwise selection is a column range applied to every line, and the
    -- swap above ordered the columns by line, not by column.
    sc, ec = math.min(sc, ec), math.max(sc, ec)
  end

  -- 'selection' = "exclusive" leaves the character under the cursor out.
  if vim.o.selection == "exclusive" then
    ec = ec - 1
    if ec < 1 or (el == sl and ec < sc) then
      return nil -- an empty selection: nothing to draw
    end
  end

  return { mode = shape, sl = sl, sc = sc, el = el, ec = ec }
end

--- Push `bufnr`'s current visual selection (or its absence) to the room the
--- open tab watches. Exported so tests can drive it directly instead of only
--- through the autocmds.
---@param bufnr integer
---@return nil
function M.send_current_selection(bufnr)
  if defaults.browser.selection_sync == false then
    M.clear()
    return
  end
  if not previewable.is(bufnr) then
    return
  end

  local sel = M.current()
  local payload = sel and vim.json.encode(sel) or "none"
  if payload == last_payload then
    return
  end
  -- `false`, not nil: vim.json.encode drops nil-valued keys, and the client
  -- needs to be TOLD the selection is gone, not left with the previous one.
  if control.send({ selection = sel or false }) then
    last_payload = payload
  end
end

--- Tell the open tab there is no selection. Used when the feature is switched
--- off mid-selection, so the highlight doesn't stay behind in the browser.
---@return nil
function M.clear()
  if last_payload == "none" then
    return
  end
  if control.send({ selection = false }) then
    last_payload = "none"
  end
end

--- Setup the ModeChanged/CursorMoved autocmds for selection sync.
---
--- Always attached, and gated per event on browser.selection_sync instead:
--- that way `:MDView selection on` takes effect on the current session rather
--- than only on the next one.
---@param group integer|nil
---@return nil
function M.attach(group)
  local function register(id)
    if group then
      autocmd_registry.register(group, id)
    end
  end

  ---@param args table
  local function on_mode_changed(args)
    -- Entering, leaving or reshaping (v -> V) a selection: never throttled.
    -- Leaving is the event whose loss would strand a highlight in the tab.
    last_sent_at = now_ms()
    M.send_current_selection(args.buf)
  end

  ---@param args table
  local function on_cursor_moved(args)
    if not VISUAL_MODES[vim.fn.mode()] then
      return -- normal-mode movement: scroll_sync's business, not ours
    end
    local wait = THROTTLE_MS - (now_ms() - last_sent_at)
    if wait > 0 then
      -- Trailing edge: without it, the last few pixels of a drag would be
      -- dropped and the browser would show a selection one throttle window
      -- short of the real one.
      if trailing_scheduled then
        return
      end
      trailing_scheduled = true
      vim.defer_fn(function()
        trailing_scheduled = false
        last_sent_at = now_ms()
        M.send_current_selection(args.buf)
      end, wait)
      return
    end
    last_sent_at = now_ms()
    M.send_current_selection(args.buf)
  end

  local mode_id = autocmd.create("ModeChanged", on_mode_changed, {
    desc = "[mdview] Mirror the visual selection into the browser preview",
    pattern = MODE_PATTERNS,
    group = group,
  })
  register(mode_id)

  local move_id = autocmd.create("CursorMoved", on_cursor_moved, {
    desc = "[mdview] Follow a growing visual selection in the browser preview",
    pattern = defaults.ft_pattern,
    group = group,
  })
  register(move_id)
end

--- Reset the cached payload — used by tests and by a session teardown, so the
--- next push is unconditional rather than deduplicated against a tab that is
--- no longer there.
---@return nil
function M.reset()
  last_payload = nil
  last_sent_at = 0
  trailing_scheduled = false
end

return M

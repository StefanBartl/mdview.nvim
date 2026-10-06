---@module 'mdview.core.spotlight_mirror'
-- What the preview needs to know about spotlight.nvim: the whole-file spotlights
-- (text, color slot, line mode, match kind) and the palette they are painted in.
--
-- spotlight.nvim is an OPTIONAL dependency, like the other companions: it is
-- looked up with pcall(require), never required, and without it (or with a
-- version that predates its read API) every function here quietly says "nothing
-- to mirror". Nothing in mdview may fail because spotlight.nvim is absent.
--
-- Pure data: no autocmds, no transport. `bindings/autocmds/spotlight_sync.lua`
-- decides WHEN to read this and send it; `adapter/ws_client.lua` sends it.
--
-- Only whole-file spotlights are mirrored (`toggle`/`add`, every occurrence).
-- A "this occurrence only" spotlight (`toggle_here`) is pinned to a buffer
-- position, which the rendered document has no counterpart for.

local M = {}

--- Bounds on what one message carries. A spotlight list is short in practice
--- (the palette has eight colors); these only stop a pathological registry from
--- building a payload the relay would refuse (it caps the body at 256 KiB).
M.MAX_ITEMS = 100
M.MAX_TEXT_BYTES = 1000

--- Matches painted per spotlight in the browser when the config gives no usable
--- number. Same value as DEFAULTS.browser.spotlight_max_matches.
M.DEFAULT_MAX_MATCHES = 500

---@class Mdview.SpotlightItem
---@field text string
---@field slot integer
---@field line boolean # whole line / block instead of just the match
---@field kind "word"|"literal" # "word" = between word boundaries, "literal" = any substring
---@field ignoreCase boolean

---@class Mdview.SpotlightColor
---@field slot integer
---@field fg string|nil # "#rrggbb"
---@field bg string|nil # "#rrggbb"
---@field bold boolean

---@class Mdview.SpotlightPayload
---@field type "spotlight"
---@field items Mdview.SpotlightItem[]
---@field colors Mdview.SpotlightColor[]
---@field max integer # matches painted per spotlight
---@field capped boolean|nil # true when items were dropped to stay inside MAX_ITEMS

--- The loaded spotlight.nvim facade, or nil when it is absent or too old to
--- have the read API (`spotlights()` arrived with the SpotlightChanged event).
---@return table|nil
function M.plugin()
  local ok, spotlight = pcall(require, "spotlight")
  if not ok or type(spotlight) ~= "table" then
    return nil
  end
  if type(spotlight.spotlights) ~= "function" then
    return nil
  end
  return spotlight
end

--- The configured per-spotlight match cap, repaired to a positive integer.
---@return integer
function M.max_matches()
  local browser = require("mdview.config").defaults.browser or {}
  local n = tonumber(browser.spotlight_max_matches)
  if not n or n ~= n or n < 1 or n == math.huge then
    return M.DEFAULT_MAX_MATCHES
  end
  return math.floor(n)
end

---@internal
---@param value any
---@return string|nil
local function hex_or_nil(value)
  if type(value) == "string" and (value:match("^#%x%x%x%x%x%x$") or value:match("^#%x%x%x%x%x%x%x%x$")) then
    return value
  end
  return nil
end

--- Build the payload for the browser from spotlight.nvim's current state.
---
--- Returns nil when spotlight.nvim is unavailable (nothing to mirror, as
--- opposed to "mirror an empty list", which clears the preview).
---@return Mdview.SpotlightPayload|nil
function M.build()
  local spotlight = M.plugin()
  if not spotlight then
    return nil
  end

  local ok, list = pcall(spotlight.spotlights, { whole_file = true })
  if not ok or type(list) ~= "table" then
    return nil
  end

  ---@type Mdview.SpotlightItem[]
  local items = {}
  local capped = false
  for _, it in ipairs(list) do
    local text = it.text
    if type(text) == "string" and text ~= "" and #text <= M.MAX_TEXT_BYTES then
      if #items >= M.MAX_ITEMS then
        capped = true
        break
      end
      items[#items + 1] = {
        text = text,
        slot = tonumber(it.slot) or 1,
        line = it.line_mode == true or it.line == true,
        kind = it.kind == "word" and "word" or "literal",
        ignoreCase = it.ignore_case == true,
      }
    elseif type(text) == "string" and text ~= "" then
      capped = true -- too long to send; say so rather than drop it silently
    end
  end

  ---@type Mdview.SpotlightColor[]
  local colors = {}
  if type(spotlight.colors) == "function" then
    local cok, palette = pcall(spotlight.colors)
    if cok and type(palette) == "table" then
      for _, c in ipairs(palette) do
        colors[#colors + 1] = {
          slot = tonumber(c.slot) or (#colors + 1),
          fg = hex_or_nil(c.fg),
          bg = hex_or_nil(c.bg),
          bold = c.bold == true,
        }
      end
    end
  end

  return {
    type = "spotlight",
    items = items,
    colors = colors,
    max = M.max_matches(),
    capped = capped or nil,
  }
end

--- The payload an `:MDView spotlight off` (or a vanished plugin) sends so the
--- preview drops every highlight: no items, no colors to change.
---@return Mdview.SpotlightPayload
function M.empty()
  return { type = "spotlight", items = {}, colors = {}, max = M.max_matches() }
end

return M

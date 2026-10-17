---@module 'mdview.core.cursor_paragraph'
-- Cursor paragraph highlight (browser.cursor_paragraph): the preview tints the
-- top-level block the Neovim cursor is in -- a paragraph up to the next blank
-- line, or a whole list, table, code block, quote or heading. The block lookup
-- happens in the browser (src/client/render/cursorParagraph.ts) against the
-- rendered document's source positions; it rides the cursor line of the
-- scroll-sync ping, so it needs scroll_sync on, like the cursor marker.
--
-- This module holds the Neovim side: the switch's value for the browser URL and
-- for the live control update, and the color, read from the highlight group
-- `MdviewCursorParagraph` (its background, links followed). Without a background
-- set on that group the preview uses its theme's own faint tint, which suits
-- both the light and the dark preview themes; a Neovim colorscheme color might
-- not, as the preview theme need not match the editor's.

local M = {}

--- Highlight group whose background colors the highlighted block.
M.HL_GROUP = "MdviewCursorParagraph"

--- Highlight namespace the group is read from: 0, the global one a colorscheme
--- and `:highlight` write to. A field so specs can read from a namespace of
--- their own instead of adding groups to the global one.
---@type integer
M.ns = 0

--- Background of `MdviewCursorParagraph` as `#rrggbb`, or nil when the group
--- has none (or does not exist).
---@return string|nil
function M.color()
  local ok, hl = pcall(vim.api.nvim_get_hl, M.ns, { name = M.HL_GROUP, link = false })
  if not ok or type(hl) ~= "table" or type(hl.bg) ~= "number" then
    return nil
  end
  return ("#%06x"):format(hl.bg)
end

--- Last color the group was seen with, kept across a `:colorscheme`.
---@type string|nil
local last_color = nil

--- The color to use, remembering it. `:colorscheme` (and a 'background'
--- switch, which reloads it) runs `:highlight clear`, which empties a group the
--- user defined once in the config too; an empty group therefore does not mean
--- "the user wants the theme's tint", and every read keeps the last color the
--- group had: the sync after a colorscheme, the browser URL of a tab opened
--- later (`:MDView start`, `:MDView open`, the tab per document a buffer switch
--- opens) and the URL `:MDView diagnose` shows. A colorscheme that defines the
--- group itself replaces it. Only `reset` -- `:MDView paragraph` switching the
--- highlight on, the user's explicit request -- takes the group as it is and
--- forgets a color the group no longer has.
---@param reset boolean|nil
---@return string|nil
function M.resolve_color(reset)
  local color = M.color()
  if color then
    last_color = color
    return color
  end
  if reset then
    last_color = nil
  end
  return last_color
end

--- Forget the remembered color (specs).
---@return nil
function M.forget()
  last_color = nil
end

--- Whether the highlight is switched on in the given browser config.
---@param browser table|nil # config.defaults.browser
---@return boolean
function M.enabled(browser)
  return type(browser) == "table" and browser.cursor_paragraph == true
end

--- Query string to append to the browser URL: `&para=1` (plus `&parabg=rrggbb`
--- when the highlight group has a background, or had one before a colorscheme
--- cleared it) when the highlight is on, else "". The color goes without its
--- `#`, which would start the URL fragment. Never forgets the kept color: it is
--- built for every tab opened, also automatically, and by `:MDView diagnose`.
---@param browser table|nil # config.defaults.browser
---@return string
function M.url_params(browser)
  if not M.enabled(browser) then
    return ""
  end
  local query = "&para=1"
  local color = M.resolve_color()
  if color then
    query = query .. "&parabg=" .. color:sub(2)
  end
  return query
end

--- Control update switching the highlight in an open tab. Carries the current
--- color too (`false` = the theme's tint), so a changed highlight group reaches
--- the preview with the next `:MDView paragraph`, and after a `:colorscheme`
--- through bindings/autocmds/cursor_paragraph_sync.lua. `reset`: see
--- resolve_color.
---@param on boolean
---@param reset boolean|nil
---@return { cursorParagraph: boolean, cursorParagraphBg: string|false }
function M.payload(on, reset)
  return { cursorParagraph = on, cursorParagraphBg = M.resolve_color(reset) or false }
end

return M

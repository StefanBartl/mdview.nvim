---@module 'mdview.bindings.autocmds.cursor_paragraph_sync'
-- Keeps the color of the cursor paragraph highlight (browser.cursor_paragraph)
-- in step with the editor: the color comes from the MdviewCursorParagraph
-- highlight group, which the tab otherwise only learns at start (URL parameter
-- `parabg`) and with the next `:MDView paragraph`. After a `:colorscheme` (or a
-- 'background' switch, which reloads the colorscheme) the tab would keep the
-- old tint, so this re-sends the control update with the current color to
-- every open tab. A group the colorscheme's `:highlight clear` emptied keeps
-- the last color it had; `false` (the theme's tint) only when it never had one.
--
-- Lives in the session augroup (MdviewAutocmds), so it exists only while a
-- preview is running, and is gated per event on browser.cursor_paragraph, so
-- nothing is sent while the highlight is off.
--
-- The read is deferred by one tick: a user config typically re-defines
-- MdviewCursorParagraph in a ColorScheme autocmd of its own, which may run
-- after this one.

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")
local cursor_paragraph = require("mdview.core.cursor_paragraph")
local autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

--- Send the current color to every open tab, when the highlight is on and a
--- session is running. A colorscheme concerns the editor, not one document, so
--- with a tab per document (behavior "new_tab"/"manual") every tab gets it,
--- whichever buffer is current. A group the colorscheme cleared keeps the last
--- color it had (cursor_paragraph.resolve_color).
---@return boolean sent
function M.sync_now()
  if not cursor_paragraph.enabled(require("mdview.config.browser").defaults) then
    return false
  end
  if not state.get_server() then
    return false
  end
  return control.broadcast(cursor_paragraph.payload(true, true))
end

--- Register the ColorScheme / OptionSet background autocmds in `group`.
---@param group integer # session augroup id
---@return nil
function M.attach(group)
  local function request()
    vim.schedule(M.sync_now)
  end

  autocmd.create({ "ColorScheme" }, request, {
    desc = "[mdview] Re-send the cursor paragraph color after a colorscheme change",
    group = group,
  })

  autocmd.create("OptionSet", request, {
    desc = "[mdview] Re-send the cursor paragraph color after 'background' changed",
    pattern = "background",
    group = group,
  })
end

return M

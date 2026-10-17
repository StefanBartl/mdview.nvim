---@module 'tests.nvim.cursor_paragraph_spec'
-- The Neovim side of the cursor paragraph highlight: its default, the color read
-- from the MdviewCursorParagraph highlight group, the URL parameters and the
-- :MDView paragraph switch with its live control update. Which block a line
-- maps to is decided in the browser (TESTS/client/cursorParagraph.test.ts).
--
-- control.send and the position ping are stubbed at their one real definition,
-- the same convention as usrcmds_write_spec.lua.

---@diagnostic disable: undefined-global, duplicate-set-field

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")
local bcfg = require("mdview.config.browser")
local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")
local cursor_paragraph = require("mdview.core.cursor_paragraph")
local paragraph = require("mdview.bindings.usrcmds.paragraph")
local live_push = require("mdview.bindings.autocmds.live_push")

local GROUP = cursor_paragraph.HL_GROUP
-- A namespace of the spec's own, so no group lands in the global one.
local NS = vim.api.nvim_create_namespace("mdview_spec_cursor_paragraph")

local orig = {
  notify = vim.notify,
  send = control.send,
  ping = scroll_sync.send_current_position,
  value = bcfg.defaults.cursor_paragraph,
  ns = cursor_paragraph.ns,
  behavior = bcfg.defaults.behavior,
  last_doc = live_push._last_doc,
}

-- `sent`: the fields of the last control.send; `rooms`: the room of every
-- control.send in order ("<current>" for one without a room).
local sent, pinged, rooms

local function reset(value, server)
  bcfg.defaults.cursor_paragraph = value
  state.set_server(server)
  sent, pinged, rooms = nil, false, {}
  vim.api.nvim_set_hl(NS, GROUP, {})
  cursor_paragraph.forget()
end

describe("cursor paragraph highlight", function()
  before_each(function()
    cursor_paragraph.ns = NS
    vim.notify = function() end
    rooms = {}
    control.send = function(fields, room)
      sent = fields
      rooms[#rooms + 1] = room or "<current>"
      return true
    end
    scroll_sync.send_current_position = function()
      pinged = true
    end
  end)

  after_each(function()
    vim.notify = orig.notify
    cursor_paragraph.ns = orig.ns
    control.send = orig.send
    scroll_sync.send_current_position = orig.ping
    bcfg.defaults.cursor_paragraph = orig.value
    bcfg.defaults.behavior = orig.behavior
    live_push._last_doc = orig.last_doc
    state.set_server(nil)
    vim.api.nvim_set_hl(NS, GROUP, {})
    cursor_paragraph.forget()
  end)

  it("is off by default", function()
    assert.is_false(require("mdview.config.DEFAULTS").browser.cursor_paragraph)
  end)

  it("reads the color from the highlight group's background, nil without one", function()
    reset(false, nil)
    assert.is_nil(cursor_paragraph.color())
    vim.api.nvim_set_hl(NS, GROUP, { bg = "#0a0b0c" })
    assert.are.equal("#0a0b0c", cursor_paragraph.color())
    vim.api.nvim_set_hl(NS, GROUP, { fg = "#ffffff" })
    assert.is_nil(cursor_paragraph.color())
  end)

  it("builds the URL parameters only when switched on, the color without its #", function()
    assert.are.equal("", cursor_paragraph.url_params({ cursor_paragraph = false }))
    assert.are.equal("", cursor_paragraph.url_params(nil))
    vim.api.nvim_set_hl(NS, GROUP, {})
    assert.are.equal("&para=1", cursor_paragraph.url_params({ cursor_paragraph = true }))
    vim.api.nvim_set_hl(NS, GROUP, { bg = "#a1b2c3" })
    assert.are.equal("&para=1&parabg=a1b2c3", cursor_paragraph.url_params({ cursor_paragraph = true }))
  end)

  it("toggles without a session: records the choice, sends nothing", function()
    reset(false, nil)
    paragraph.run()
    assert.is_true(bcfg.defaults.cursor_paragraph)
    assert.is_nil(sent)
    paragraph.run("toggle")
    assert.is_false(bcfg.defaults.cursor_paragraph)
  end)

  it("on with a session pushes the switch with the current color and pings the position", function()
    reset(false, {})
    vim.api.nvim_set_hl(NS, GROUP, { bg = "#102030" })
    paragraph.run("on")
    assert.is_true(bcfg.defaults.cursor_paragraph)
    assert.are.same({ cursorParagraph = true, cursorParagraphBg = "#102030" }, sent)
    assert.is_true(pinged)
  end)

  it("off with a session pushes the switch, a missing color as false, no ping", function()
    reset(true, {})
    paragraph.run("off")
    assert.is_false(bcfg.defaults.cursor_paragraph)
    assert.are.same({ cursorParagraph = false, cursorParagraphBg = false }, sent)
    assert.is_false(pinged)
  end)

  it("rejects an unknown action and changes nothing", function()
    reset(true, {})
    paragraph.run("sideways")
    assert.is_true(bcfg.defaults.cursor_paragraph)
    assert.is_nil(sent)
  end)

  describe("after a colorscheme change", function()
    local sync = require("mdview.bindings.autocmds.cursor_paragraph_sync")
    local group

    --- Fire `event` (with `pattern`), then let the deferred read run.
    ---@param event string
    ---@param pattern string|nil
    local function fire(event, pattern)
      vim.api.nvim_exec_autocmds(event, { pattern = pattern, modeline = false })
      vim.wait(200, function()
        return sent ~= nil
      end, 10)
    end

    before_each(function()
      group = vim.api.nvim_create_augroup("MdviewCursorParagraphSyncSpec", { clear = true })
      sync.attach(group)
    end)

    after_each(function()
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end)

    it("re-sends the new color to the open tab when the highlight is on", function()
      reset(true, {})
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#445566" })
      fire("ColorScheme")
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = "#445566" }, sent)
    end)

    it("falls back to the theme's tint (false) when the group lost its background", function()
      reset(true, {})
      fire("ColorScheme")
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = false }, sent)
    end)

    it("keeps the last color when the colorscheme's :highlight clear emptied the group", function()
      reset(true, {})
      -- Defined once in the config, then `:colorscheme` clears it.
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#2a3350" })
      fire("ColorScheme")
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = "#2a3350" }, sent)
      sent = nil
      vim.api.nvim_set_hl(NS, GROUP, {})
      fire("ColorScheme")
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = "#2a3350" }, sent)
    end)

    it("a colorscheme that defines the group itself replaces the kept color", function()
      reset(true, {})
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#2a3350" })
      fire("ColorScheme")
      sent = nil
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#0f0e0d" })
      fire("ColorScheme")
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = "#0f0e0d" }, sent)
    end)

    it("forgets the kept color once :MDView paragraph finds the group empty", function()
      reset(true, {})
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#2a3350" })
      fire("ColorScheme")
      vim.api.nvim_set_hl(NS, GROUP, {})
      paragraph.run("on")
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = false }, sent)
      sent = nil
      fire("ColorScheme")
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = false }, sent)
    end)

    it("reads the group after a ColorScheme autocmd registered later redefined it", function()
      reset(true, {})
      -- The user's own ColorScheme autocmd, defined after mdview's: it runs
      -- second, so only a read deferred past the event sees its color.
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
          vim.api.nvim_set_hl(NS, GROUP, { bg = "#778899" })
        end,
      })
      fire("ColorScheme")
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = "#778899" }, sent)
    end)

    it("reaches every open tab with a tab per document, from an unnamed buffer too", function()
      reset(true, {})
      bcfg.defaults.behavior = "new_tab"
      live_push._last_doc = { ["/notes/b.md"] = "/notes/b.md", ["/notes/a.md"] = "/notes/a.md" }
      local scratch = vim.api.nvim_create_buf(false, true)
      local prev = vim.api.nvim_get_current_buf()
      vim.api.nvim_set_current_buf(scratch)
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#445566" })
      fire("ColorScheme")
      vim.api.nvim_set_current_buf(prev)
      vim.api.nvim_buf_delete(scratch, { force = true })
      assert.are.same({ "/notes/a.md", "/notes/b.md" }, rooms)
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = "#445566" }, sent)
    end)

    it("keeps the one-tab routing with behavior = reuse", function()
      reset(true, {})
      bcfg.defaults.behavior = "reuse"
      live_push._last_doc = { ["/notes/a.md"] = "/notes/a.md", ["/notes/b.md"] = "/notes/b.md" }
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#445566" })
      fire("ColorScheme")
      assert.are.same({ "<current>" }, rooms)
    end)

    it("re-sends after a 'background' switch too", function()
      reset(true, {})
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#010203" })
      fire("OptionSet", "background")
      assert.are.same({ cursorParagraph = true, cursorParagraphBg = "#010203" }, sent)
    end)

    it("sends nothing while the highlight is off", function()
      reset(false, {})
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#445566" })
      fire("ColorScheme")
      assert.is_nil(sent)
    end)

    it("sends nothing without a session", function()
      reset(true, nil)
      vim.api.nvim_set_hl(NS, GROUP, { bg = "#445566" })
      fire("ColorScheme")
      assert.is_nil(sent)
    end)

    it("sends nothing once the augroup is gone (session stopped)", function()
      reset(true, {})
      vim.api.nvim_del_augroup_by_id(group)
      fire("ColorScheme")
      assert.is_nil(sent)
    end)
  end)
end)

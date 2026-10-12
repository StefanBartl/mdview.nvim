---@module 'tests.nvim.write_back_reuse_spec'
-- Verifies that the browser -> buffer write-backs (checkbox toggle, text field)
-- edit the buffer of the document the tab is SHOWING, as far as Neovim knows it:
-- the document it last pushed into the tab's room. Under
-- `browser.behavior = "reuse"` the tab's key is the path of the first document
-- for the whole session while the tab follows the active buffer, and a reloaded
-- tab does not know the document at all.
--
-- Also: only buffers mdview previews are written to, a field edit replaces just
-- the lines that differ (marks survive), a buffer that is not modifiable is
-- refused instead of raising, and a toggle that arrives after the lines moved
-- does not tick the neighbour.

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")
local live = require("mdview.bindings.autocmds.live_push")
local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local bcfg = require("mdview.config.browser")

local function make_buf(name, lines)
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, name)
  vim.bo[b].filetype = "markdown"
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end

local room = make_buf("mdview_spec_reuse_room.md", { "# Room", "- [ ] in the room" })
local shown = make_buf("mdview_spec_reuse_shown.md", {
  "# Shown",
  "- [ ] on screen",
  '<input type="text" name="title">',
  "",
  "tail",
})
vim.api.nvim_set_current_buf(shown)

local ROOM = assert(normalize.path(vim.api.nvim_buf_get_name(room)))
local SHOWN = assert(normalize.path(vim.api.nvim_buf_get_name(shown)))

local function lines(b)
  return vim.api.nvim_buf_get_lines(b, 0, -1, false)
end

local ws_orig = { content = ws.send_content, doc = ws.send_doc, control = ws.send_control }
local announced

describe("browser write-backs under browser.behavior = reuse", function()
  before_each(function()
    vim.bo[shown].modifiable = true
    vim.bo[shown].filetype = "markdown"
    vim.api.nvim_buf_set_lines(shown, 0, -1, false, {
      "# Shown",
      "- [ ] on screen",
      '<input type="text" name="title">',
      "",
      "tail",
    })
    vim.api.nvim_buf_set_lines(room, 0, -1, false, { "# Room", "- [ ] in the room" })
    -- the tab's room is ROOM (the first document); Neovim last pushed SHOWN into it
    live._last_doc = { [ROOM] = SHOWN }
    announced = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    ws.send_content = function() end
    ---@diagnostic disable-next-line: duplicate-set-field
    ws.send_doc = function(key, path)
      announced[#announced + 1] = { key = key, path = path }
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    ws.send_control = function() end
  end)

  after_each(function()
    live._last_doc = {}
    ws.send_content, ws.send_doc, ws.send_control = ws_orig.content, ws_orig.doc, ws_orig.control
    state.set_preview_key(nil)
    bcfg.defaults.behavior = "reuse"
  end)

  it("a checkbox toggle goes to the document the room holds, not to the room's own buffer", function()
    inbound._handle_toggle(ROOM, 2, true, SHOWN)
    assert.are.equal("- [x] on screen", lines(shown)[2])
    assert.are.equal("- [ ] in the room", lines(room)[2])
  end)

  it("a reloaded tab (no doc) still reaches the shown document", function()
    inbound._handle_toggle(ROOM, 2, true) -- the client had no /doc ping after F5
    assert.are.equal("- [x] on screen", lines(shown)[2])
    assert.are.equal("- [ ] in the room", lines(room)[2])
    inbound._handle_field(ROOM, "title", "Hello", vim.NIL)
    assert.are.equal('<input type="text" name="title" value="Hello">', lines(shown)[3])
  end)

  it("a tab that is behind (names another document) is refused, nothing is guessed", function()
    inbound._handle_toggle(ROOM, 2, true, ROOM) -- the room's own document: stale ping
    assert.are.equal("- [ ] in the room", lines(room)[2])
    assert.are.equal("- [ ] on screen", lines(shown)[2])
  end)

  it("a room Neovim never pushed into is not written to, whatever doc says", function()
    live._last_doc = {}
    inbound._handle_toggle(ROOM, 2, true, SHOWN)
    inbound._handle_field(ROOM, "title", "Hello", SHOWN)
    assert.are.equal("- [ ] on screen", lines(shown)[2])
    assert.are.equal("- [ ] in the room", lines(room)[2])
  end)

  it("a buffer switch announces the document, so the write-back follows it", function()
    local switch = require("mdview.bindings.autocmds.buffer_switch")
    state.set_preview_key(ROOM)
    bcfg.defaults.behavior = "reuse"
    live._last_doc = { [ROOM] = ROOM } -- the tab was showing the first document
    local orig_wait = ws.wait_ready
    ---@diagnostic disable-next-line: duplicate-set-field
    ws.wait_ready = function(cb)
      cb(true)
    end
    local ok = switch.resync(shown)
    ws.wait_ready = orig_wait
    assert.is_true(ok)
    assert.are.equal(SHOWN, live.shown_document(ROOM))
    assert.are.equal(1, #announced)
    assert.are.equal(SHOWN, announced[1].path)

    inbound._handle_toggle(ROOM, 2, true) -- no doc: the room says it
    assert.are.equal("- [x] on screen", lines(shown)[2])
    assert.are.equal("- [ ] in the room", lines(room)[2])
  end)

  it("a field edit goes to the shown document", function()
    inbound._handle_field(ROOM, "title", "Hello", SHOWN)
    assert.are.equal('<input type="text" name="title" value="Hello">', lines(shown)[3])
    assert.are.same({ "# Room", "- [ ] in the room" }, lines(room))
  end)

  it("a field edit replaces only the lines that differ (marks on other lines survive)", function()
    local ns = vim.api.nvim_create_namespace("mdview_spec_reuse")
    local mark_tail = vim.api.nvim_buf_set_extmark(shown, ns, 4, 0, {}) -- "tail"
    local mark_head = vim.api.nvim_buf_set_extmark(shown, ns, 0, 0, {}) -- "# Shown"
    inbound._handle_field(ROOM, "title", "Hello", SHOWN)
    assert.are.equal(4, vim.api.nvim_buf_get_extmark_by_id(shown, ns, mark_tail, {})[1])
    assert.are.equal(0, vim.api.nvim_buf_get_extmark_by_id(shown, ns, mark_head, {})[1])
  end)

  it("a field edit that changes nothing leaves the buffer alone", function()
    vim.api.nvim_buf_set_lines(shown, 2, 3, false, { '<input type="text" name="title" value="Same">' })
    local tick = vim.api.nvim_buf_get_changedtick(shown)
    inbound._handle_field(ROOM, "title", "Same", SHOWN)
    assert.are.equal(tick, vim.api.nvim_buf_get_changedtick(shown))
  end)

  it("a field name is matched at an attribute boundary (data-name is another attribute)", function()
    vim.api.nvim_buf_set_lines(shown, 2, 3, false, {
      '<input data-name="title">',
      '<input name="title">',
    })
    inbound._handle_field(ROOM, "title", "X", SHOWN)
    assert.are.equal('<input data-name="title">', lines(shown)[3])
    assert.are.equal('<input name="title" value="X">', lines(shown)[4])
  end)

  it("a toggle whose line moved since the render does not tick the neighbour", function()
    vim.api.nvim_buf_set_lines(shown, 0, -1, false, { "# Shown", "- [ ] one", "- [ ] two" })
    -- the browser ticked "two" at line 3; a text field gained a line before it
    vim.api.nvim_buf_set_lines(shown, 1, 1, false, { "inserted" })
    inbound._handle_toggle(ROOM, 3, true, SHOWN, "- [ ] two")
    assert.are.same({ "# Shown", "inserted", "- [ ] one", "- [ ] two" }, lines(shown))
    -- the line it meant is where it is now: that one is ticked
    inbound._handle_toggle(ROOM, 4, true, SHOWN, "- [ ] two")
    assert.are.same({ "# Shown", "inserted", "- [ ] one", "- [x] two" }, lines(shown))
  end)

  it("a toggle in a buffer loaded with a trailing \\r keeps it", function()
    vim.api.nvim_buf_set_lines(shown, 0, -1, false, { "# Shown\r", "- [ ] one\r" })
    inbound._handle_toggle(ROOM, 2, true, SHOWN, "- [ ] one")
    assert.are.same({ "# Shown\r", "- [x] one\r" }, lines(shown))
  end)

  it("never writes to a buffer mdview does not preview", function()
    vim.bo[shown].filetype = "lua"
    local before = lines(shown)
    inbound._handle_toggle(ROOM, 2, true, SHOWN)
    inbound._handle_field(ROOM, "title", "Hello", SHOWN)
    assert.are.same(before, lines(shown))
  end)

  it("refuses a buffer that is not modifiable and does not raise", function()
    vim.bo[shown].modifiable = false
    local before = lines(shown)
    assert.has_no.errors(function()
      inbound._handle_toggle(ROOM, 2, true, SHOWN)
      inbound._handle_field(ROOM, "title", "Hello", SHOWN)
    end)
    assert.are.same(before, lines(shown))
  end)

  it("ignores a fractional line number", function()
    local before = lines(shown)
    inbound._handle_toggle(ROOM, 1.5, true, SHOWN)
    assert.are.same(before, lines(shown))
  end)
end)

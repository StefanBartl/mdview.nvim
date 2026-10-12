---@module 'tests.nvim.write_back_reuse_spec'
-- Verifies that the browser -> buffer write-backs (checkbox toggle, text field)
-- edit the buffer of the document the tab is SHOWING (`doc`), not the buffer
-- named by the tab's room key. Under `browser.behavior = "reuse"` the tab's key
-- is the path of the first document for the whole session while the tab follows
-- the active buffer.
--
-- Also: only buffers mdview previews are written to, a field edit replaces just
-- the lines that differ (marks survive), and a buffer that is not modifiable is
-- refused instead of raising.

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")

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
  end)

  it("a checkbox toggle goes to the shown document, not to the room's", function()
    inbound._handle_toggle(ROOM, 2, true, SHOWN)
    assert.are.equal("- [x] on screen", lines(shown)[2])
    assert.are.equal("- [ ] in the room", lines(room)[2])
  end)

  it("without doc the room's buffer is used (standalone, older clients)", function()
    inbound._handle_toggle(ROOM, 2, true)
    assert.are.equal("- [x] in the room", lines(room)[2])
    assert.are.equal("- [ ] on screen", lines(shown)[2])
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

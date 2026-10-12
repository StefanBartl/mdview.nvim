---@module 'tests.nvim.block_edit_spec'
-- Verifies inbound_poll._handle_edit replaces a block's source lines in the
-- buffer showing a document, and only while those lines are still what the
-- preview was rendered from (`expected`). This is the :MDView start path;
-- standalone applies the same rule in the relay
-- (native/server/internal/source/edit.go).

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")
local config = require("mdview.config")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "mdview_spec_block_edit.md")
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "markdown"

local KEY = assert(normalize.path(vim.api.nvim_buf_get_name(buf)), "the fixture buffer has a name")

local other = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(other, "mdview_spec_block_edit_other.md")
vim.bo[other].filetype = "markdown"
local OTHER_KEY = assert(normalize.path(vim.api.nvim_buf_get_name(other)), "the other buffer has a name")

local function set(lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local function all()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local edit_blocks0 = config.defaults.edit_blocks

describe("inbound_poll._handle_edit", function()
  before_each(function()
    config.defaults.edit_blocks = true
    vim.bo[buf].modifiable = true
    vim.bo[buf].filetype = "markdown"
    set({ "# Title", "", "first line", "second line", "", "tail" })
    vim.api.nvim_buf_set_lines(other, 0, -1, false, { "# Other", "", "other text" })
  end)

  after_each(function()
    config.defaults.edit_blocks = edit_blocks0
  end)

  it("replaces one line", function()
    inbound._handle_edit(KEY, 1, 1, "# Title", "# New title")
    assert.are.same({ "# New title", "", "first line", "second line", "", "tail" }, all())
  end)

  it("replaces a block with a different number of lines", function()
    inbound._handle_edit(KEY, 3, 4, "first line\nsecond line", "one\ntwo\nthree")
    assert.are.same({ "# Title", "", "one", "two", "three", "", "tail" }, all())
    inbound._handle_edit(KEY, 3, 5, "one\ntwo\nthree", "single")
    assert.are.same({ "# Title", "", "single", "", "tail" }, all())
  end)

  it("accepts CRLF in expected and text", function()
    inbound._handle_edit(KEY, 3, 4, "first line\r\nsecond line", "a\r\nb")
    assert.are.same({ "# Title", "", "a", "b", "", "tail" }, all())
  end)

  it("refuses an edit whose lines changed since the render", function()
    local before = all()
    inbound._handle_edit(KEY, 3, 4, "first line\nOLD second line", "x")
    assert.are.same(before, all())
  end)

  it("refuses a range past the end of the buffer", function()
    local before = all()
    inbound._handle_edit(KEY, 5, 9, "x", "y")
    assert.are.same(before, all())
  end)

  it("ignores an invalid range, a fractional line number and an unknown key", function()
    local before = all()
    inbound._handle_edit(KEY, 0, 1, "# Title", "z")
    inbound._handle_edit(KEY, 3, 2, "first line", "z")
    inbound._handle_edit(KEY, 1.5, 2, "# Title", "z")
    inbound._handle_edit(KEY, 1, 2 ^ 40, "# Title", "z")
    inbound._handle_edit("no/such.md", 1, 1, "# Title", "z")
    assert.are.same(before, all())
  end)

  it("is one undo step", function()
    vim.bo[buf].undolevels = 1000
    -- start a fresh undo block so the earlier `set` is not part of it
    vim.cmd("let &undolevels = &undolevels")
    local before = all()
    inbound._handle_edit(KEY, 3, 4, "first line\nsecond line", "x\ny\nz")
    assert.are_not.same(before, all())
    vim.cmd("silent! undo")
    assert.are.same(before, all())
  end)

  it("edits the buffer of `doc`, not the one of the room key (reuse behavior)", function()
    -- the tab's room is KEY, but the tab is showing OTHER_KEY's document
    inbound._handle_edit(KEY, 3, 3, "other text", "edited other", OTHER_KEY)
    assert.are.same({ "# Other", "", "edited other" }, vim.api.nvim_buf_get_lines(other, 0, -1, false))
    assert.are.same({ "# Title", "", "first line", "second line", "", "tail" }, all())
  end)

  it("does nothing while block editing is off (an edit queued before `:MDView edit off`)", function()
    config.defaults.edit_blocks = false
    local before = all()
    inbound._handle_edit(KEY, 1, 1, "# Title", "# Off")
    assert.are.same(before, all())
  end)

  it("edits only buffers mdview previews, not any loaded buffer", function()
    vim.bo[buf].filetype = "lua"
    local before = all()
    inbound._handle_edit(KEY, 1, 1, "# Title", "-- rewritten")
    assert.are.same(before, all())
  end)

  it("refuses a buffer that is not modifiable and does not raise", function()
    vim.bo[buf].modifiable = false
    local before = all()
    assert.has_no.errors(function()
      inbound._handle_edit(KEY, 1, 1, "# Title", "# Locked")
    end)
    assert.are.same(before, all())
  end)

  it("tells the tab when an edit was not applied", function()
    local control = require("mdview.adapter.control")
    local sent = {}
    local orig = control.send
    control.send = function(fields, room)
      sent[#sent + 1] = { fields = fields, room = room }
      return true
    end
    local ok, err = pcall(inbound._handle_edit, KEY, 3, 4, "not the lines", "x")
    control.send = orig
    assert.is_true(ok, err)
    assert.are.equal(1, #sent)
    assert.are.equal(KEY, sent[1].room)
    assert.is_truthy(sent[1].fields.notice:find("Not saved", 1, true))
  end)
end)

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
local live = require("mdview.bindings.autocmds.live_push")
local ws = require("mdview.adapter.ws_client")
local control = require("mdview.adapter.control")

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
local ws_orig = { content = ws.send_content, doc = ws.send_doc, control = ws.send_control }
local control_orig = control.send

-- what the tab was told (control.send is how a refusal reaches it)
local told

describe("inbound_poll._handle_edit", function()
  before_each(function()
    config.defaults.edit_blocks = true
    vim.bo[buf].modifiable = true
    vim.bo[buf].filetype = "markdown"
    set({ "# Title", "", "first line", "second line", "", "tail" })
    vim.api.nvim_buf_set_lines(other, 0, -1, false, { "# Other", "", "other text" })
    -- the room of the tab (KEY) holds the document of `buf`
    live._last_doc[KEY] = KEY
    told = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    ws.send_content = function() end
    ---@diagnostic disable-next-line: duplicate-set-field
    ws.send_doc = function() end
    ---@diagnostic disable-next-line: duplicate-set-field
    ws.send_control = function() end
    ---@diagnostic disable-next-line: duplicate-set-field
    control.send = function(fields, room)
      told[#told + 1] = { fields = fields, room = room }
      return true
    end
  end)

  after_each(function()
    config.defaults.edit_blocks = edit_blocks0
    live._last_doc[KEY] = nil
    ws.send_content, ws.send_doc, ws.send_control = ws_orig.content, ws_orig.doc, ws_orig.control
    control.send = control_orig
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

  it("compares without the \\r a CRLF file keeps when loaded as unix, and writes the same ending back", function()
    set({ "# Title\r", "\r", "first line\r", "second line\r", "\r", "tail\r" })
    inbound._handle_edit(KEY, 3, 4, "first line\nsecond line", "one\ntwo\nthree")
    assert.are.same({ "# Title\r", "\r", "one\r", "two\r", "three\r", "\r", "tail\r" }, all())
  end)

  it("refuses an edit whose lines changed since the render, and tells the tab", function()
    local before = all()
    inbound._handle_edit(KEY, 3, 4, "first line\nOLD second line", "x")
    assert.are.same(before, all())
    assert.are.equal(1, #told)
    assert.are.equal(KEY, told[1].room)
    assert.is_truthy(told[1].fields.notice:find("Not saved", 1, true))
  end)

  it("refuses a range past the end of the buffer", function()
    local before = all()
    inbound._handle_edit(KEY, 5, 9, "x", "y")
    assert.are.same(before, all())
    assert.are.equal(1, #told)
  end)

  it("ignores an invalid range, a fractional line number and a huge one", function()
    local before = all()
    inbound._handle_edit(KEY, 0, 1, "# Title", "z")
    inbound._handle_edit(KEY, 3, 2, "first line", "z")
    inbound._handle_edit(KEY, 1.5, 2, "# Title", "z")
    inbound._handle_edit(KEY, 1, 2 ^ 40, "# Title", "z")
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

  it("edits the document the room holds, not what the request names (reuse behavior)", function()
    -- the tab's room is KEY, and Neovim last pushed OTHER_KEY's document into it
    live._last_doc[KEY] = OTHER_KEY
    inbound._handle_edit(KEY, 3, 3, "other text", "edited other")
    assert.are.same({ "# Other", "", "edited other" }, vim.api.nvim_buf_get_lines(other, 0, -1, false))
    assert.are.same({ "# Title", "", "first line", "second line", "", "tail" }, all())
  end)

  it("a tab that is behind (names another document than the room holds) is refused, not guessed", function()
    live._last_doc[KEY] = OTHER_KEY
    local before_other = vim.api.nvim_buf_get_lines(other, 0, -1, false)
    inbound._handle_edit(KEY, 3, 3, "other text", "edited", KEY) -- the tab still shows `buf`
    assert.are.same(before_other, vim.api.nvim_buf_get_lines(other, 0, -1, false))
    assert.are.same({ "# Title", "", "first line", "second line", "", "tail" }, all())
    assert.are.equal(1, #told)
  end)

  it("a room Neovim never pushed a document into is not a room of this session", function()
    live._last_doc[KEY] = nil
    local before = all()
    inbound._handle_edit(KEY, 1, 1, "# Title", "# Hijacked", KEY)
    assert.are.same(before, all())
    assert.are.equal(1, #told)
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
    assert.are.equal(1, #told)
  end)

  it("refuses a buffer that is not modifiable and does not raise", function()
    vim.bo[buf].modifiable = false
    local before = all()
    assert.has_no.errors(function()
      inbound._handle_edit(KEY, 1, 1, "# Title", "# Locked")
    end)
    assert.are.same(before, all())
    assert.are.equal(1, #told)
  end)
end)

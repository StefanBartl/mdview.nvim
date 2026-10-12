---@module 'tests.nvim.field_attrs_spec'
-- Review round 3, item 23: inbound_poll._handle_field reads a tag attribute by
-- attribute, like native/server/internal/source/field.go (field_attrs_test.go):
-- `data-value` is not `value`, a `>` in a quoted value does not end the tag,
-- single quotes are read, and a `name=` inside another value is not the field.

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")
local live = require("mdview.bindings.autocmds.live_push")
local ws = require("mdview.adapter.ws_client")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "mdview_spec_field_attrs.md")
vim.bo[buf].filetype = "markdown"
vim.api.nvim_set_current_buf(buf)
local KEY = assert(normalize.path(vim.api.nvim_buf_get_name(buf)))

local ws_orig = { content = ws.send_content, doc = ws.send_doc, control = ws.send_control }

local function set_and_edit(lines, name, value)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  inbound._handle_field(KEY, name, value, KEY)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

describe("inbound_poll._handle_field, attributes", function()
  before_each(function()
    live._last_doc[KEY] = KEY
    ws.send_content = function() end
    ws.send_doc = function() end
    ws.send_control = function() end
  end)
  after_each(function()
    live._last_doc[KEY] = nil
    ws.send_content, ws.send_doc, ws.send_control = ws_orig.content, ws_orig.doc, ws_orig.control
  end)

  it("data-value is another attribute: a value is inserted next to it", function()
    assert.are.same(
      { '<input name="t" data-value="a" value="new">' },
      set_and_edit({ '<input name="t" data-value="a">' }, "t", "new")
    )
  end)

  it("replaces a value that holds a '>' and keeps what follows", function()
    assert.are.same(
      { '<input name="t" value="x" size="3">' },
      set_and_edit({ '<input name="t" value="a>b" size="3">' }, "t", "x")
    )
  end)

  it("reads single-quoted name and value", function()
    assert.are.same(
      { [[<input name='t' value="x">]] },
      set_and_edit({ [[<input name='t' value='it "is" here'>]] }, "t", "x")
    )
  end)

  it("a name= inside another attribute's value is not the field", function()
    assert.are.same(
      { [[<input name="other" title='x name="t" y'>]], '<input name="t" value="v">' },
      set_and_edit({ [[<input name="other" title='x name="t" y'>]], '<input name="t">' }, "t", "v")
    )
  end)

  it("a textarea whose opening tag holds a '>'", function()
    assert.are.same(
      { '<textarea title="a>b" name="n">new</textarea>' },
      set_and_edit({ '<textarea title="a>b" name="n">old</textarea>' }, "n", "new")
    )
  end)

  it("username= and data-name= are not the field called x", function()
    local out = set_and_edit({ '<input username="x">', '<input data-name="x">', '<input name="x">' }, "x", "1")
    assert.are.same({ '<input username="x">', '<input data-name="x">', '<input name="x" value="1">' }, out)
  end)
end)

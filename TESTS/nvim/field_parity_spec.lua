---@module 'tests.nvim.field_parity_spec'
-- The same cases as native/server/internal/source/field_parity_test.go: the
-- relay and Neovim must write byte-identical output for a field edit.

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")
local live = require("mdview.bindings.autocmds.live_push")
local ws = require("mdview.adapter.ws_client")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "mdview_spec_field_parity.md")
vim.bo[buf].filetype = "markdown"
vim.api.nvim_set_current_buf(buf)
local KEY = assert(normalize.path(vim.api.nvim_buf_get_name(buf)))

local ws_orig = { content = ws.send_content, doc = ws.send_doc, control = ws.send_control }

local CASES = {
  { "unquoted name and value", [[<input name=t value=abc>]], "t", "x", [[<input name=t value="x">]] },
  { "value without a value", [[<input name="t" value= >]], "t", "x", [[<input name="t" value="x">]] },
  { "attribute names in capitals", [[<input NAME="t" VALUE="a">]], "t", "x", [[<input NAME="t" value="x">]] },
  {
    "a custom element is no input",
    '<input-x name="t">\n<input name="t">',
    "t",
    "x",
    '<input-x name="t">\n<input name="t" value="x">',
  },
  { "quotes inside a quoted name stay", [[<input name="'t'">]], "'t'", "x", [[<input name="'t'" value="x">]] },
  {
    "an unclosed quote hides only its own tag",
    '<input name=a value="x>\n<input name="t">',
    "t",
    "v",
    '<input name=a value="x>\n<input name="t" value="v">',
  },
  { "a bare attribute is kept", [[<input disabled name="t">]], "t", "x", [[<input disabled name="t" value="x">]] },
}

describe("inbound_poll._handle_field, parity with the relay", function()
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

  for _, c in ipairs(CASES) do
    it(c[1], function()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(c[2], "\n", { plain = true }))
      inbound._handle_field(KEY, c[3], c[4], KEY)
      assert.are.same(vim.split(c[5], "\n", { plain = true }), vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)
  end
end)

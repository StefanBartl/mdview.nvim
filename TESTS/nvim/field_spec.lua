---@module 'tests.nvim.field_spec'
-- Verifies inbound_poll._handle_field writes a syncable text field's value back
-- into the buffer showing a key, located by the field's `name` attribute (raw
-- HTML has no source position). This is the :MDView start path; standalone
-- applies field edits in the relay. Mirrors native/server/internal/source's
-- field_test.go so both write byte-identical output.

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "mdview_spec_field.md")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"# Form",
	"",
	'<input type="text" name="title">',
	'<input name="done" type="text" value="old">',
	'<textarea name="notes">a',
	"b</textarea>",
})
vim.api.nvim_set_current_buf(buf)

local KEY = normalize.path(vim.api.nvim_buf_get_name(buf))

local function line(n)
	return vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1]
end

describe("inbound_poll._handle_field", function()
	it("inserts a value attribute on an input with none", function()
		inbound._handle_field(KEY, "title", "Hello")
		assert.are.equal('<input type="text" name="title" value="Hello">', line(3))
	end)

	it("replaces an existing value attribute", function()
		inbound._handle_field(KEY, "done", "new")
		assert.are.equal('<input name="done" type="text" value="new">', line(4))
	end)

	it("HTML-escapes the value", function()
		inbound._handle_field(KEY, "title", '<b> & "x"')
		assert.are.equal('<input type="text" name="title" value="&lt;b&gt; &amp; &quot;x&quot;">', line(3))
	end)

	it("rewrites a multi-line textarea body", function()
		inbound._handle_field(KEY, "notes", "one\ntwo\nthree")
		assert.are.equal('<textarea name="notes">one', line(5))
		assert.are.equal("two", line(6))
		assert.are.equal("three</textarea>", line(7))
	end)

	it("declines an unknown field name", function()
		local before = line(3)
		inbound._handle_field(KEY, "nope", "x")
		assert.are.equal(before, line(3))
	end)

	it("ignores an unknown key (no matching buffer)", function()
		local before = line(4)
		inbound._handle_field("no/such.md", "done", "zzz")
		assert.are.equal(before, line(4))
	end)
end)

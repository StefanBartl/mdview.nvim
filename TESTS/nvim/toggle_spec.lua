---@module 'tests.nvim.toggle_spec'
-- Verifies inbound_poll._handle_toggle flips the GFM task-list checkbox on the
-- given source line of the buffer showing a key, and leaves non-checkbox lines
-- alone. This is the :MDView start path (the relay queues the toggle, Neovim
-- edits its own buffer); standalone applies toggles in the relay instead.

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "mdview_spec_toggle.md")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"# Tasks",
	"",
	"- [ ] alpha",
	"- [x] beta",
	"  * [ ] nested",
	"plain paragraph",
})
vim.api.nvim_set_current_buf(buf)

local KEY = normalize.path(vim.api.nvim_buf_get_name(buf))

local function line(n)
	return vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1]
end

describe("inbound_poll._handle_toggle", function()
	it("checks an unchecked box on the given line", function()
		inbound._handle_toggle(KEY, 3, true)
		assert.are.equal("- [x] alpha", line(3))
	end)

	it("unchecks a checked box", function()
		inbound._handle_toggle(KEY, 4, false)
		assert.are.equal("- [ ] beta", line(4))
	end)

	it("preserves indentation and bullet style", function()
		inbound._handle_toggle(KEY, 5, true)
		assert.are.equal("  * [x] nested", line(5))
	end)

	it("leaves a non-checkbox line untouched", function()
		inbound._handle_toggle(KEY, 6, true)
		assert.are.equal("plain paragraph", line(6))
	end)

	it("is a no-op when already in the requested state", function()
		inbound._handle_toggle(KEY, 3, true) -- already [x] from the first test
		assert.are.equal("- [x] alpha", line(3))
	end)

	it("ignores an out-of-range line", function()
		inbound._handle_toggle(KEY, 999, true)
		assert.are.equal(6, vim.api.nvim_buf_line_count(buf))
	end)

	it("ignores an unknown key (no matching buffer)", function()
		inbound._handle_toggle("no/such/file.md", 3, false)
		-- line 3 unchanged by the unknown-key call
		assert.are.equal("- [x] alpha", line(3))
	end)
end)

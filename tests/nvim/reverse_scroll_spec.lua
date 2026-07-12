---@module 'tests.nvim.reverse_scroll_spec'
-- Verifies inbound_poll's reverse-scroll cursor math: a 0..1 ratio maps to the
-- proportional line of the previewed buffer shown in a window.

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")

local KEY = normalize.path("C:/proj/rs.md")

-- A 10-line buffer shown in the current window, named to match KEY.
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "C:/proj/rs.md")
local lines = {}
for i = 1, 10 do
	lines[i] = "line " .. i
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.api.nvim_set_current_buf(buf)

local function cursor_line_for(ratio)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	inbound._handle_scroll(KEY, ratio)
	return vim.api.nvim_win_get_cursor(0)[1]
end

describe("inbound_poll reverse-scroll cursor mapping (10 lines)", function()
	it("ratio 0 -> first line", function()
		assert.are.equal(1, cursor_line_for(0))
	end)
	it("ratio 0.5 -> middle", function()
		assert.are.equal(6, cursor_line_for(0.5))
	end)
	it("ratio 1 -> last line", function()
		assert.are.equal(10, cursor_line_for(1.0))
	end)
	it("clamps ratios above 1 to the last line", function()
		assert.are.equal(10, cursor_line_for(1.5))
	end)
	it("clamps negative ratios to the first line", function()
		assert.are.equal(1, cursor_line_for(-0.3))
	end)
	it("ignores an unknown key (no matching buffer)", function()
		vim.api.nvim_win_set_cursor(0, { 4, 0 })
		inbound._handle_scroll(normalize.path("C:/proj/nope.md"), 1.0)
		assert.are.equal(4, vim.api.nvim_win_get_cursor(0)[1]) -- unchanged
	end)
end)

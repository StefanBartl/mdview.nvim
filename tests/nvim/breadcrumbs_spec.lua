---@module 'tests.nvim.breadcrumbs_spec'
-- Verifies mdview.core.breadcrumbs: nearest-heading detection (incl. fenced-code
-- skip), (doc, heading) dedupe, and the Markdown outline formatter.

---@diagnostic disable: undefined-global

local crumbs = require("mdview.core.breadcrumbs")

-- A markdown buffer with two H2 sections, an H3 subsection, and a fenced code
-- block that contains a line starting with "#".
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "mdview_spec_crumbs.md")
vim.bo[buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"intro text", -- 1  (top, no heading yet)
	"## Overview", -- 2
	"body", -- 3
	"```sh", -- 4
	"# not a heading", -- 5  (inside fence)
	"```", -- 6
	"### Details", -- 7
	"more", -- 8
	"## Wrap up", -- 9
})
vim.api.nvim_set_current_buf(buf)

local function record_at(line)
	vim.api.nvim_win_set_cursor(0, { line, 0 })
	return crumbs.record(buf)
end

describe("breadcrumbs.record heading detection + dedupe", function()
	it("records (top) before the first heading", function()
		crumbs.clear()
		assert.is_true(record_at(1))
		assert.are.equal("(top)", crumbs.snapshot()[1].heading)
	end)

	it("records the governing heading and dedupes within a section", function()
		crumbs.clear()
		record_at(1) -- (top)
		assert.is_true(record_at(3)) -- moves into ## Overview
		assert.are.equal("## Overview", crumbs.snapshot()[2].heading)
		assert.is_false(record_at(2)) -- still ## Overview -> no new entry
		assert.are.equal(2, #crumbs.snapshot())
	end)

	it("ignores a '#' inside a fenced code block", function()
		crumbs.clear()
		record_at(6) -- line 6 is the closing fence; nearest real heading is Overview
		assert.are.equal("## Overview", crumbs.snapshot()[1].heading)
	end)

	it("tracks deeper and sibling headings", function()
		crumbs.clear()
		record_at(3) -- ## Overview
		record_at(8) -- ### Details
		record_at(9) -- ## Wrap up
		local h = vim.tbl_map(function(e)
			return e.heading
		end, crumbs.snapshot())
		assert.are.same({ "## Overview", "### Details", "## Wrap up" }, h)
	end)
end)

describe("breadcrumbs.format", function()
	it("emits a Markdown outline grouped by document", function()
		crumbs.clear()
		record_at(3) -- ## Overview
		record_at(8) -- ### Details
		local out = crumbs.format()
		assert.is_true(out[1]:match("^# Session breadcrumbs") ~= nil)
		-- a document header (## <basename>) and heading bullets are present
		local joined = table.concat(out, "\n")
		assert.is_true(joined:find("## mdview_spec_crumbs.md", 1, true) ~= nil)
		assert.is_true(joined:find("— ## Overview", 1, true) ~= nil)
		assert.is_true(joined:find("— ### Details", 1, true) ~= nil)
	end)

	it("reports empty state after clear", function()
		crumbs.clear()
		local out = crumbs.format()
		assert.is_true(table.concat(out, "\n"):find("no breadcrumbs", 1, true) ~= nil)
	end)
end)

---@module 'tests.lua.line_diff_spec'
-- Unit tests for mdview.utils.line_diff (pure Lua, no vim). The edit it emits
-- must reproduce `new` from `old` when applied with the same semantics the
-- browser client uses (Array.splice(start, count, ...lines), 0-based start) —
-- so alongside shape checks we assert the round-trip for a spread of cases.

---@diagnostic disable: undefined-global

local line_diff = require("mdview.utils.line_diff")

-- Mirror of src/client/render/diffDoc.ts's splice application.
local function apply(old, e)
	local a = {}
	for i, v in ipairs(old) do
		a[i] = v
	end
	if not e then
		return a
	end
	for _ = 1, e.count do
		table.remove(a, e.start + 1)
	end
	for k = #e.lines, 1, -1 do
		table.insert(a, e.start + 1, e.lines[k])
	end
	return a
end

describe("mdview.utils.line_diff", function()
	it("returns nil when nothing changed", function()
		assert.is_nil(line_diff({ "a", "b", "c" }, { "a", "b", "c" }))
		assert.is_nil(line_diff({}, {}))
	end)

	it("emits a 0-based single-line replace", function()
		assert.are.same({ start = 1, count = 1, lines = { "B" } }, line_diff({ "a", "b", "c" }, { "a", "B", "c" }))
	end)

	it("emits an append as count=0 at the end", function()
		assert.are.same({ start = 3, count = 0, lines = { "d" } }, line_diff({ "a", "b", "c" }, { "a", "b", "c", "d" }))
	end)

	it("emits a deletion as empty lines", function()
		assert.are.same({ start = 1, count = 1, lines = {} }, line_diff({ "a", "b", "c" }, { "a", "c" }))
	end)

	it("emits a prepend at start 0", function()
		assert.are.same({ start = 0, count = 0, lines = { "x" } }, line_diff({ "a", "b", "c" }, { "x", "a", "b", "c" }))
	end)

	it("round-trips a spread of edits", function()
		local cases = {
			{ { "a", "b", "c" }, { "a", "B", "c" } },
			{ { "a", "b", "c" }, { "a", "b", "c", "d" } },
			{ { "a", "b", "c" }, { "a", "c" } },
			{ { "a", "b", "c" }, { "x", "a", "b", "c" } },
			{ { "a", "b", "c", "d", "e" }, { "a", "X", "Y", "d", "e" } },
			{ {}, { "a", "b" } },
			{ { "a", "b" }, {} },
			{ { "l1", "l2", "l3" }, { "l1", "l2 edited", "l3" } },
		}
		for _, c in ipairs(cases) do
			local old, new = c[1], c[2]
			assert.are.same(new, apply(old, line_diff(old, new)))
		end
	end)

	it("treats nil inputs as empty", function()
		assert.are.same({ start = 0, count = 0, lines = { "a" } }, line_diff(nil, { "a" }))
		assert.is_nil(line_diff(nil, {}))
	end)
end)

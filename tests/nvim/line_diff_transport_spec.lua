---@module 'tests.nvim.line_diff_transport_spec'
-- Verifies ws_client.send_content's versioning under experimental.line_diff:
-- first send is a full snapshot, subsequent changes are diffs, an unchanged
-- send is a no-op, opts.full forces a full, and reset_diff_state re-fulls.

---@diagnostic disable: undefined-global

-- setup() is done once by the harness; enable line_diff directly for this spec.
require("mdview.config").defaults.experimental.line_diff = true
local ws = require("mdview.adapter.ws_client")

-- Capture full snapshots (they go via send_markdown). Diffs go via a local
-- http_post_nonblocking (curl/jobstart) — stub jobstart so nothing is spawned;
-- we assert the diff path was taken via the version/since bookkeeping instead.
local fulls = {}
ws.send_markdown = function(_, body)
	fulls[#fulls + 1] = body
end
vim.fn.jobstart = function()
	return 1
end

local KEY = "C:/proj/doc.md"

local function decode_full(body)
	assert(body:sub(1, 1) == "\3", "full envelope must be \\x03-tagged")
	return vim.json.decode(body:sub(2))
end

describe("ws_client.send_content line-diff versioning", function()
	ws.reset_diff_state()
	fulls = {}

	it("first send is a full snapshot at version 1", function()
		ws.send_content(KEY, { "# T", "a", "b" })
		assert.are.equal(1, #fulls)
		local env = decode_full(fulls[1])
		assert.are.equal("f", env.t)
		assert.are.equal(1, env.v)
		assert.are.equal("# T\na\nb", env.text)
		assert.are.equal(1, ws._diff_ver[KEY])
		assert.are.equal(0, ws._diff_since[KEY])
	end)

	it("a changed send is a diff (version bumps, no new full)", function()
		ws.send_content(KEY, { "# T", "A", "b" })
		assert.are.equal(1, #fulls) -- still only the one full
		assert.are.equal(2, ws._diff_ver[KEY])
		assert.are.equal(1, ws._diff_since[KEY])
	end)

	it("an unchanged send is a no-op", function()
		ws.send_content(KEY, { "# T", "A", "b" })
		assert.are.equal(2, ws._diff_ver[KEY]) -- unchanged
		assert.are.equal(1, ws._diff_since[KEY])
	end)

	it("opts.full forces a fresh full snapshot", function()
		ws.send_content(KEY, { "# T", "A", "b", "c" }, { full = true })
		assert.are.equal(2, #fulls)
		assert.are.equal(3, decode_full(fulls[2]).v)
		assert.are.equal(3, ws._diff_ver[KEY])
		assert.are.equal(0, ws._diff_since[KEY]) -- reset by the full
	end)

	it("reset_diff_state makes the next send a full again", function()
		ws.reset_diff_state(KEY)
		assert.is_nil(ws._diff_ver[KEY])
		ws.send_content(KEY, { "fresh" })
		assert.are.equal(3, #fulls)
		assert.are.equal(1, decode_full(fulls[3]).v) -- version restarts
	end)
end)

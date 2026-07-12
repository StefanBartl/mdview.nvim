---@module 'tests.nvim.buffer_switch_spec'
-- Verifies live_push routing under each browser.behavior: "reuse" targets the
-- open tab's preview key, "new_tab"/"manual" target the buffer's own path, and
-- "reuse" with no open tab falls back to the buffer's path.

---@diagnostic disable: undefined-global

-- setup() is done once by the harness; specs adjust config directly.
local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local live = require("mdview.bindings.autocmds.live_push")
local bcfg = require("mdview.config.browser")

-- Capture where content is routed. live_push calls send_content; stub it.
local last_key
local orig = ws.send_content
ws.send_content = function(key)
	last_key = key
end

local function make_md_buffer(name)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buf, name)
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# doc", "body" })
	return buf
end

describe("live_push routing by browser.behavior", function()
	local buf = make_md_buffer("C:/proj/B.md")

	it("reuse -> targets the open tab's preview key", function()
		state.set_preview_key("C:/proj/A.md")
		bcfg.defaults.behavior = "reuse"
		last_key = nil
		live.push_buffer_changes(buf)
		assert.are.equal("C:/proj/A.md", last_key)
	end)

	it("new_tab -> targets the buffer's own path", function()
		state.set_preview_key("C:/proj/A.md")
		bcfg.defaults.behavior = "new_tab"
		last_key = nil
		live.push_buffer_changes(buf)
		assert.are.equal("C:/proj/B.md", last_key)
	end)

	it("manual -> targets the buffer's own path", function()
		bcfg.defaults.behavior = "manual"
		last_key = nil
		live.push_buffer_changes(buf)
		assert.are.equal("C:/proj/B.md", last_key)
	end)

	it("reuse with no open tab -> falls back to the buffer's path", function()
		state.set_preview_key(nil)
		bcfg.defaults.behavior = "reuse"
		last_key = nil
		live.push_buffer_changes(buf)
		assert.are.equal("C:/proj/B.md", last_key)
	end)

	-- restore
	ws.send_content = orig
end)

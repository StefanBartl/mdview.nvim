---@module 'tests.nvim.log_scratch_spec'
-- Regression for the E95 "Buffer with this name already exists" crash:
-- M.show_ring used to hardcode nvim_buf_set_name("mdview://log") on every
-- call, which threw once a previous invocation's window/buffer was still
-- around. Calls show_ring directly (bypassing the :MDView command layer,
-- which the harness deliberately doesn't register — see harness.lua) twice
-- in a row, the way a user re-running `:MDView log` in the same session would.

---@diagnostic disable: undefined-global

local usrcmd_log = require("mdview.bindings.usrcmds.log")

describe("usrcmds.log show_ring buffer reuse", function()
	it("does not error when called twice with the old window still open", function()
		usrcmd_log.show_ring(nil)
		local ok, err = pcall(usrcmd_log.show_ring, usrcmd_log.LEVELS.warn)
		assert.is_true(ok, tostring(err))
	end)

	it("reuses a single mdview://log buffer instead of creating a new one", function()
		local bufnr = vim.fn.bufnr("mdview://log")
		assert(bufnr ~= -1, "expected mdview://log buffer to exist")

		usrcmd_log.show_ring(nil)

		local count = 0
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(b):match("mdview://log$") then
				count = count + 1
			end
		end
		assert.are.equal(1, count)
		assert.are.equal(bufnr, vim.fn.bufnr("mdview://log"))
	end)

	it("updates the buffer content on repeat calls", function()
		usrcmd_log.show_ring(usrcmd_log.LEVELS.error)
		local bufnr = vim.fn.bufnr("mdview://log")
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		assert(#lines > 0, "expected at least one line in the log scratch buffer")
	end)
end)

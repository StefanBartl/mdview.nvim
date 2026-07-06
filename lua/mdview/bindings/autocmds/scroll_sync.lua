---@module 'mdview.bindings.autocmds.scroll_sync'
-- Sends the cursor's current line (and total line count) to the relay on
-- CursorMoved/CursorMovedI, throttled, so the browser preview can scroll to
-- follow — the nvim-to-browser half of bidirectional scrolling (see
-- docs/Roadmap/Roadmap.md's bonus features). Gated behind
-- mdview.config.defaults.scroll_sync (default true).

local api = vim.api
local ws_client = require("mdview.adapter.ws_client")
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")
local normalize = require("mdview.helper.normalize")
local defaults = require("mdview.config").defaults
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

local last_sent_at = 0

---@return integer
local function now_ms()
	local uv = vim.uv or vim.loop
	return uv.now()
end

---@param bufnr integer
local function send_current_position(bufnr)
	local ft = safe_buf_get_option(bufnr, "filetype") or ""
	if ft ~= "markdown" and ft ~= "md" then
		return
	end

	local path = normalize.path(api.nvim_buf_get_name(bufnr))
	if not path or path == "" then
		return
	end

	local line = api.nvim_win_get_cursor(0)[1]
	local total = api.nvim_buf_line_count(bufnr)
	ws_client.send_scroll(path, line, total)
end

--- Setup CursorMoved/CursorMovedI autocmd for scroll sync.
---@param group integer|nil
function M.attach(group)
	if not defaults.scroll_sync then
		return
	end

	local opts = {
		desc = "[mdview] Send cursor position to browser preview (scroll sync)",
		pattern = defaults.ft_pattern,
		callback = function(args)
			local throttle_ms = defaults.scroll_sync_throttle_ms or 150
			local t = now_ms()
			if t - last_sent_at < throttle_ms then
				return
			end
			last_sent_at = t
			send_current_position(args.buf)
		end,
	}
	if group then
		opts.group = group
	end

	local id = api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, opts)
	if group then
		autocmd_registry.register(group, id)
	end
end

return M

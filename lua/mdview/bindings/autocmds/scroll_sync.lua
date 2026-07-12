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

-- When reverse-scroll moves the cursor programmatically, that fires
-- CursorMoved, which would send an outgoing ping and bounce back to the browser
-- (feedback loop). inbound_poll calls M.suppress() around such moves so the next
-- brief window of outgoing pings is skipped.
local suppress_until = 0

--- Suppress outgoing scroll pings for `ms` (default 250) — used by the
--- reverse-scroll handler around a programmatic cursor move.
---@param ms integer|nil
---@return nil
function M.suppress(ms)
	suppress_until = now_ms() + (ms or 250)
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

	-- Where the line should sit in the browser viewport (0 = top, 1 = bottom).
	local viewfrac
	if defaults.scroll_sync_mode == "cursor" then
		-- Mirror the cursor's height within the nvim window.
		local winline = vim.fn.winline() -- 1-based screen row of the cursor
		local height = api.nvim_win_get_height(0)
		viewfrac = (winline - 1) / math.max(1, height - 1)
	else
		viewfrac = defaults.scroll_sync_top_offset or 0.08
	end

	ws_client.send_scroll(path, line, total, viewfrac)
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
			if t < suppress_until then
				return -- cursor moved by reverse-scroll; don't echo it back
			end
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

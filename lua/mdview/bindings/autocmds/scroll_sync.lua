---@module 'mdview.bindings.autocmds.scroll_sync'
-- Sends the cursor's current line (and total line count) to the relay on
-- CursorMoved/CursorMovedI, throttled, so the browser preview can scroll to
-- follow — the nvim-to-browser half of bidirectional scrolling. Gated behind
-- mdview.config.defaults.scroll_sync (default true).

local api = vim.api
local ws_client = require("mdview.adapter.ws_client")
local previewable = require("mdview.helper.previewable")
local target_key = require("mdview.helper.target_key")
local defaults = require("mdview.config").defaults
local autocmd = require("lib.nvim.bindings.autocmd")
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

local last_sent_at = 0

---@internal
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

-- Persistent pause switch (:MDViewSync). Unlike suppress (a brief time window
-- around a programmatic move), this stays on until explicitly resumed, so you
-- can scroll to a reference spot in Neovim without dragging the preview along.
local paused = false

--- Suppress outgoing scroll pings for `ms` (default 250) — used by the
--- reverse-scroll handler around a programmatic cursor move.
---@param ms integer|nil
---@return nil
function M.suppress(ms)
	suppress_until = now_ms() + (ms or 250)
end

--- Pause/resume outgoing scroll-sync pings (:MDViewSync). While paused, cursor
--- moves in Neovim no longer scroll the preview or move its cursor marker.
---@param on boolean
---@return nil
function M.set_paused(on)
	paused = on == true
end

--- @return boolean
function M.is_paused()
	return paused
end

--- Flip the pause state and return the new value.
---@return boolean
function M.toggle_paused()
	paused = not paused
	return paused
end

--- Send bufnr's current cursor line/column (and total line count) to the
--- room the open tab watches. Exported (like live_push.push_buffer_changes)
--- so tests can call it directly instead of only through the throttled
--- CursorMoved/CursorMovedI autocmd.
---@param bufnr integer
---@return nil
function M.send_current_position(bufnr)
	if not previewable.is(bufnr) then
		return
	end

	-- Route to the room the open tab actually watches (browser.behavior
	-- "reuse" follows the active buffer via state.preview_key, so a scroll
	-- ping to the buffer's own path after switching buffers would land in a
	-- room nobody's listening to — see target_key.lua and DONE.md BUGS).
	local target = target_key.resolve(bufnr)
	if not target or target == "" then
		return
	end

	local pos = api.nvim_win_get_cursor(0)
	local line = pos[1]
	local col = pos[2] -- 0-based byte column, for the cursor caret
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

	ws_client.send_scroll(target, line, total, viewfrac, col)
end

--- Setup CursorMoved/CursorMovedI autocmd for scroll sync.
---@param group integer|nil
function M.attach(group)
	if not defaults.scroll_sync then
		return
	end

	local function on_cursor_moved(args)
		if paused then
			return -- :MDViewSync pause — don't drag the preview along
		end
		local throttle_ms = defaults.scroll_sync_throttle_ms or 150
		local t = now_ms()
		if t < suppress_until then
			return -- cursor moved by reverse-scroll; don't echo it back
		end
		if t - last_sent_at < throttle_ms then
			return
		end
		last_sent_at = t
		M.send_current_position(args.buf)
	end

	local opts = {
		desc = "[mdview] Send cursor position to browser preview (scroll sync)",
		pattern = defaults.ft_pattern,
	}
	if group then
		opts.group = group
	end

	local id = autocmd.create({ "CursorMoved", "CursorMovedI" }, on_cursor_moved, opts)
	if group then
		autocmd_registry.register(group, id)
	end
end

return M

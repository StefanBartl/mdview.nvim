---@module 'mdview.bindings.autocmds.buffer_switch'
-- Applies `browser.behavior` when you switch to a different markdown buffer
-- while a preview session is running:
--   "reuse"   — the one open tab follows you: push the entered buffer's content
--               to the room that tab watches (state.preview_key).
--   "new_tab" — open a fresh preview tab for the entered buffer (once per file).
--   "manual"  — do nothing (open other files explicitly with :MDViewOpen).
--
-- Registered in the main mdview augroup (attached on :MDViewStart, torn down on
-- :MDViewStop). Distinct from bufenter.lua, which only snapshots content.

local api = vim.api
local ws_client = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local normalize = require("mdview.helper.normalize")
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")
local log = require("mdview.helper.log")
local defaults = require("mdview.config").defaults
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

-- Last markdown path we acted on, so BufEnter (which fires on every window
-- focus, not just real buffer changes) doesn't re-push the same buffer. Reset
-- each attach cycle.
---@type string|nil
M._last = nil

-- Paths we've already opened a tab for in "new_tab" mode, so revisiting a file
-- doesn't spawn a duplicate tab. Reset each attach cycle.
---@type table<string, boolean>
M._opened = {}

---@param bufnr integer
---@return string|nil # normalized markdown path, or nil if not an eligible buffer
local function eligible_path(bufnr)
	local ft = safe_buf_get_option(bufnr, "filetype") or ""
	if ft ~= "markdown" and ft ~= "md" then
		return nil
	end
	local name = api.nvim_buf_get_name(bufnr)
	if name == "" then
		return nil
	end
	return normalize.path(name)
end

---@param bufnr integer
local function on_switch(bufnr)
	-- Only relevant while a browser session is running. In tab-preview mode the
	-- nvim tab already follows the buffer via its own sync, so skip entirely.
	if not state.get_server() then
		return
	end
	if defaults.open_preview_tab then
		return
	end

	local path = eligible_path(bufnr)
	if not path then
		return
	end
	if M._last == path then
		return -- same buffer as last time (BufEnter fires on window focus too)
	end
	M._last = path

	local behavior = require("mdview.config.browser").defaults.behavior or "reuse"
	if behavior == "manual" then
		return
	end

	if behavior == "reuse" then
		local preview_key = state.get_preview_key()
		if type(preview_key) ~= "string" or preview_key == "" then
			return -- no tab open to follow
		end
		-- Push this buffer's content into the open tab's room so it switches to
		-- the newly-focused file (even without an edit to trigger live_push).
		ws_client.wait_ready(function(ok)
			if not ok then
				return
			end
			local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
			ws_client.send_markdown(preview_key, table.concat(lines, "\n"), { immediate = true })
			log.debug("reuse: pushed " .. path .. " to preview room " .. preview_key, nil, "bufswitch", true)
		end, ws_client.WAIT_READY_TIMEOUT)
		return
	end

	if behavior == "new_tab" then
		-- Respect the user's autostart preference; if they don't want tabs
		-- opened automatically, don't spawn new ones on buffer switch either.
		if not require("mdview.config.browser").defaults.browser_autostart then
			return
		end
		if M._opened[path] then
			return
		end
		M._opened[path] = true
		-- open() previews the *current* buffer; BufEnter has already made this
		-- buffer current, so this opens a tab for `path`.
		vim.schedule(function()
			require("mdview").open()
		end)
	end
end

-- Reset per-session dedup state. Called on attach so a new :MDViewStart starts
-- clean and a stale "_last" from a previous session can't suppress the first
-- switch.
---@return nil
function M.reset()
	M._last = nil
	M._opened = {}
end

--- Setup the BufEnter behavior dispatch in the given augroup.
---@param group integer|nil
function M.attach(group)
	M.reset()
	local opts = {
		desc = "[mdview] Apply browser.behavior on markdown buffer switch",
		pattern = defaults.ft_pattern,
		callback = function(args)
			on_switch(args.buf)
		end,
	}
	if group then
		opts.group = group
	end
	local id = api.nvim_create_autocmd("BufEnter", opts)
	autocmd_registry.register(group, id)
end

return M

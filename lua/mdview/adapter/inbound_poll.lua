---@module 'mdview.adapter.inbound_poll'
-- Browser->Neovim polling bridge for the features that need to push events
-- upstream (Neovim has no WebSocket client, and the relay stays a dumb
-- byte-forwarder). While a session is active it polls, per tick:
--   * GET /nav        (experimental.click_navigate) — clicked links to open
--   * GET /scrollback (experimental.reverse_scroll) — browser scroll position
-- Only the enabled endpoints are polled; the timer runs only if at least one is
-- enabled. curl is already a hard dependency; a click/scroll is latency-tolerant
-- enough for a poll.

local uv = vim.uv or vim.loop

local notify = require("lib.nvim.notify").create("").notify

local M = {}

local INTERVAL_MS = 250
local timer = nil
local nav_inflight = false
local scroll_inflight = false

---@param endpoint string
---@return string
local function url_for(endpoint)
	local port = vim.g.mdview_server_port or 43219
	local token = require("mdview.core.state").get_token() or ""
	return string.format("http://localhost:%d/%s?token=%s", port, endpoint, vim.uri_encode(token))
end

---@return table
local function experimental()
	return require("mdview.config").defaults.experimental or {}
end

-- ---- click-to-navigate -----------------------------------------------------

---@param key string
---@param href string
-- Absolute path? (Unix "/…" or Windows "C:/…" / "C:\…"). Back/forward
-- navigation sends absolute document paths; relative links are resolved against
-- the source document's directory.
---@param p string
---@return boolean
local function is_absolute(p)
	return p:match("^/") ~= nil or p:match("^%a:[/\\]") ~= nil
end

local function handle_nav(key, href)
	if type(key) ~= "string" or type(href) ~= "string" or href == "" then
		return
	end
	local target
	if is_absolute(href) then
		target = href
	else
		local dir = vim.fn.fnamemodify(key, ":h")
		target = vim.fn.simplify(dir .. "/" .. href)
	end
	local norm = require("mdview.helper.normalize").path(target)
	if norm then
		target = norm
	end
	if vim.fn.filereadable(target) ~= 1 then
		notify("[mdview] click-navigate: file not found: " .. target, vim.log.levels.WARN)
		return
	end
	pcall(vim.cmd.edit, vim.fn.fnameescape(target))
end

local function poll_nav()
	if nav_inflight then
		return
	end
	nav_inflight = true
	vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", url_for("nav") }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data then
				return
			end
			local body = vim.trim(table.concat(data, "\n"))
			if body == "" or body == "null" then
				return
			end
			local ok, arr = pcall(vim.json.decode, body)
			if not ok or type(arr) ~= "table" then
				return
			end
			vim.schedule(function()
				for _, r in ipairs(arr) do
					if type(r) == "table" then
						handle_nav(r.key, r.href)
					end
				end
			end)
		end,
		on_exit = function()
			nav_inflight = false
		end,
	})
end

-- ---- reverse scroll (browser -> nvim) --------------------------------------

-- Find the loaded buffer whose (normalized) name matches `key`.
---@param key string
---@return integer|nil
local function buf_for_key(key)
	local normalize = require("mdview.helper.normalize")
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) then
			local name = normalize.path(vim.api.nvim_buf_get_name(b))
			if name == key then
				return b
			end
		end
	end
	return nil
end

---@param key string
---@param ratio number
local function handle_scroll(key, ratio)
	if type(key) ~= "string" or type(ratio) ~= "number" then
		return
	end
	local buf = buf_for_key(key)
	if not buf then
		return
	end
	-- Only move the cursor in a window actually showing that buffer.
	local win
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(w) == buf then
			win = w
			break
		end
	end
	if not win then
		return
	end
	local total = vim.api.nvim_buf_line_count(buf)
	local line = math.floor(ratio * (total - 1) + 0.5) + 1
	if line < 1 then
		line = 1
	elseif line > total then
		line = total
	end
	-- Suppress the outgoing ping this cursor move would otherwise trigger.
	require("mdview.bindings.autocmds.scroll_sync").suppress(250)
	pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
end

local function poll_scroll()
	if scroll_inflight then
		return
	end
	scroll_inflight = true
	vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", url_for("scrollback") }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data then
				return
			end
			local body = vim.trim(table.concat(data, "\n"))
			if body == "" or body == "null" then
				return
			end
			local ok, obj = pcall(vim.json.decode, body)
			if not ok or type(obj) ~= "table" or obj.key == nil then
				return
			end
			vim.schedule(function()
				handle_scroll(obj.key, obj.ratio)
			end)
		end,
		on_exit = function()
			scroll_inflight = false
		end,
	})
end

-- ---- lifecycle -------------------------------------------------------------

local function tick()
	if not require("mdview.core.state").get_server() then
		return
	end
	if vim.fn.executable("curl") ~= 1 then
		return
	end
	local exp = experimental()
	if exp.click_navigate == true then
		poll_nav()
	end
	if exp.reverse_scroll == true then
		poll_scroll()
	end
end

--- Start polling. No-op unless at least one inbound feature is enabled.
--- Safe to call repeatedly.
---@return nil
function M.start()
	if timer then
		return
	end
	local exp = experimental()
	if not (exp.click_navigate == true or exp.reverse_scroll == true) then
		return
	end
	timer = uv.new_timer()
	timer:start(INTERVAL_MS, INTERVAL_MS, vim.schedule_wrap(tick))
end

--- Stop polling. Safe to call when not started.
---@return nil
function M.stop()
	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
		timer = nil
	end
	nav_inflight = false
	scroll_inflight = false
end

-- Exposed for headless tests.
M._handle_nav = handle_nav
M._handle_scroll = handle_scroll

return M

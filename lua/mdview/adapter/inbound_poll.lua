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
local toggle_inflight = false
local field_inflight = false

---@internal
---@param endpoint string
---@return string
local function url_for(endpoint)
	local port = vim.g.mdview_server_port or 43219
	local token = require("mdview.core.state").get_token() or ""
	return string.format("http://localhost:%d/%s?token=%s", port, endpoint, vim.uri_encode(token))
end

---@internal
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
---@internal
---@param p string
---@return boolean
local function is_absolute(p)
	return p:match("^/") ~= nil or p:match("^%a:[/\\]") ~= nil
end

---@internal
---@param key string
---@param href string
---@return nil
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

---@internal
---@return nil
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
---@internal
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

---@internal
---@param key string
---@param ratio number
---@return nil
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

---@internal
---@return nil
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

-- ---- task-list checkbox toggle (browser -> nvim buffer) --------------------

-- Flip the GFM task-list checkbox on 1-based `line` of the buffer showing
-- `key` to `checked`, then push the change so the preview reflects it. Standalone
-- mode never reaches here (the relay edits the file itself); this is the
-- :MDView start path, where the buffer — possibly with unsaved edits — is the
-- source of truth the relay must not touch. A line that no longer holds a task
-- marker is left alone (a re-render can race a rapid edit).
---@internal
---@param key string
---@param line integer
---@param checked boolean
---@return nil
local function handle_toggle(key, line, checked)
	if type(key) ~= "string" or type(line) ~= "number" or line < 1 then
		return
	end
	local buf = buf_for_key(key)
	if not buf or not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	if line > vim.api.nvim_buf_line_count(buf) then
		return
	end
	local cur = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
	if not cur then
		return
	end
	local pre, state, post = cur:match("^(%s*[-*+] %[)([ xX])(%].*)$")
	if not pre then
		return -- not a checkbox line; don't corrupt it
	end
	local want = checked and "x" or " "
	if state == want then
		return -- already in the requested state
	end
	vim.api.nvim_buf_set_lines(buf, line - 1, line, false, { pre .. want .. post })
	-- nvim_buf_set_lines doesn't fire TextChanged, so push explicitly.
	pcall(require("mdview.bindings.autocmds.live_push").push_buffer_changes, buf, { full = true })
end

---@internal
---@return nil
local function poll_toggle()
	if toggle_inflight then
		return
	end
	toggle_inflight = true
	vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", url_for("toggle") }, {
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
						handle_toggle(r.key, r.line, r.checked)
					end
				end
			end)
		end,
		on_exit = function()
			toggle_inflight = false
		end,
	})
end

-- ---- text field write-back (browser -> nvim buffer) ------------------------

local escape_attr, escape_text
do
	-- HTML-escape for a double-quoted attribute value / element text, mirroring
	-- native/server/internal/source/field.go so start mode and standalone write
	-- byte-identical output.
	local function replace(s, from, to)
		return (s:gsub(from, to))
	end
	escape_attr = function(v)
		v = replace(v, "&", "&amp;")
		v = replace(v, "<", "&lt;")
		v = replace(v, ">", "&gt;")
		v = replace(v, '"', "&quot;")
		return v
	end
	escape_text = function(v)
		v = replace(v, "&", "&amp;")
		v = replace(v, "<", "&lt;")
		v = replace(v, ">", "&gt;")
		return v
	end
end

-- Replace the whole buffer's text and push the result. Used for field edits,
-- which can change content across lines (a multi-line textarea body); a
-- single-line set like handle_toggle's isn't enough.
---@internal
---@param buf integer
---@param new_text string
---@return nil
local function apply_buffer_text(buf, new_text)
	local lines = vim.split(new_text, "\n", { plain = true })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	pcall(require("mdview.bindings.autocmds.live_push").push_buffer_changes, buf, { full = true })
end

-- Set the syncable field named `name` in the buffer showing `key` to `value`,
-- then push. Located by the `name` attribute (raw HTML has no source position),
-- like the Go side. Standalone never reaches here (the relay edits the file).
---@internal
---@param key string
---@param name string
---@param value string
---@return nil
local function handle_field(key, name, value)
	if type(key) ~= "string" or type(name) ~= "string" or name == "" or type(value) ~= "string" then
		return
	end
	local buf = buf_for_key(key)
	if not buf or not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
	local q = vim.pesc(name)

	-- textarea first (explicit close, unambiguous body). `.` in Lua patterns
	-- matches newlines, so a multi-line body is handled.
	local ta_open, ta_body_start = text:find('<textarea[^>]*name="' .. q .. '"[^>]*>')
	if ta_open then
		local close_start = text:find("</textarea>", ta_body_start + 1, true)
		if close_start then
			local new_text = text:sub(1, ta_body_start) .. escape_text(value) .. text:sub(close_start)
			apply_buffer_text(buf, new_text)
			return
		end
	end

	-- input: find the tag by name, then set/insert its value attribute.
	local in_start, in_end = text:find('<input[^>]*name="' .. q .. '"[^>]*>')
	if in_start then
		local tag = text:sub(in_start, in_end)
		local repl = 'value="' .. escape_attr(value) .. '"'
		local new_tag
		if tag:find('value="[^"]*"') then
			new_tag = (tag:gsub('value="[^"]*"', function()
				return repl
			end, 1))
		elseif tag:sub(-2) == "/>" then
			new_tag = tag:sub(1, -3):gsub("%s+$", "") .. " " .. repl .. "/>"
		else
			new_tag = tag:sub(1, -2):gsub("%s+$", "") .. " " .. repl .. ">"
		end
		local new_text = text:sub(1, in_start - 1) .. new_tag .. text:sub(in_end + 1)
		apply_buffer_text(buf, new_text)
	end
end

---@internal
---@return nil
local function poll_field()
	if field_inflight then
		return
	end
	field_inflight = true
	vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", url_for("field") }, {
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
						handle_field(r.key, r.name, r.value)
					end
				end
			end)
		end,
		on_exit = function()
			field_inflight = false
		end,
	})
end

-- ---- lifecycle -------------------------------------------------------------

---@internal
---@return nil
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
	local cfg = require("mdview.config").defaults
	if cfg.sync_checkboxes ~= false then
		poll_toggle()
	end
	if cfg.sync_fields ~= false then
		poll_field()
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
	local cfg = require("mdview.config").defaults
	local sync = cfg.sync_checkboxes ~= false or cfg.sync_fields ~= false
	if not (exp.click_navigate == true or exp.reverse_scroll == true or sync) then
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
	toggle_inflight = false
	field_inflight = false
end

-- Exposed for headless tests.
M._handle_nav = handle_nav
M._handle_scroll = handle_scroll
M._handle_toggle = handle_toggle
M._handle_field = handle_field

return M

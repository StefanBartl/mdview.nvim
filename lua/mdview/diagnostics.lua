---@module 'mdview.diagnostics'
-- One-shot diagnostics for mdview.nvim: gathers the state of every component
-- (Neovim, dependencies, install cache, config, running relay, health probe,
-- recent internal log ring) into a single plain-text report written to a
-- file. The point is a hand-off: run :MDViewDiagnose, then send the printed
-- file so an issue can be reproduced without a live session.
--
-- Read-only except for probing /health and writing the report; never starts,
-- stops, or mutates a session.

local fn = vim.fn
local is_windows = require("lib.nvim.cross.platform.is_windows")

local M = {}

---@param lines string[]
---@param key string
---@param value any
local function kv(lines, key, value)
	lines[#lines + 1] = ("  %-22s %s"):format(key .. ":", tostring(value))
end

---@param cmd string
---@return boolean
local function has_exe(cmd)
	return fn.executable(cmd) == 1
end

-- Synchronous localhost GET (diagnostics run on demand, blocking is fine).
---@param url string
---@return string # trimmed body or an error marker
local function curl_get(url)
	if not has_exe("curl") then
		return "(curl not found)"
	end
	local out = fn.system({ "curl", "-sS", "--max-time", "2", url })
	if vim.v.shell_error ~= 0 then
		return ("(curl failed, exit %d)"):format(vim.v.shell_error)
	end
	return (out:gsub("%s+$", ""))
end

--- Build the diagnostics report as a list of lines.
---@return string[]
function M.collect()
	local lines = {}
	local function section(title)
		lines[#lines + 1] = ""
		lines[#lines + 1] = "== " .. title .. " =="
	end

	lines[#lines + 1] = "mdview.nvim diagnostics — " .. os.date("%Y-%m-%d %H:%M:%S")

	section("Environment")
	kv(lines, "nvim version", tostring(vim.version()))
	local uv = vim.uv or vim.loop
	local uname = uv and uv.os_uname and uv.os_uname() or {}
	kv(lines, "os", (uname.sysname or "?") .. " " .. (uname.machine or "?"))
	kv(lines, "is_windows", is_windows())
	kv(lines, "has GUI/display", (fn.has("gui_running") == 1) or (vim.env.DISPLAY ~= nil) or is_windows())

	section("Dependencies")
	local has_lib = pcall(require, "lib.nvim.logger")
	kv(lines, "lib.nvim", has_lib and "present" or "MISSING (hard dependency)")
	kv(lines, "curl", has_exe("curl"))
	kv(lines, "tar", has_exe("tar"))
	kv(lines, "vim.ui.open", type(vim.ui and vim.ui.open) == "function")

	section("Install cache")
	local ok_install, install = pcall(require, "mdview.adapter.install")
	if ok_install then
		local status = install.status()
		kv(lines, "server binary", status.binary_installed and "cached" or "NOT installed")
		kv(lines, "  path", status.binary_path)
		kv(lines, "client bundle", status.client_installed and "cached" or "NOT installed")
		kv(lines, "  path", status.client_dir)
	else
		kv(lines, "install module", "FAILED to load: " .. tostring(install))
	end

	section("Config (browser + key fields)")
	local defaults = require("mdview.config").defaults
	kv(lines, "server_port", defaults.server_port)
	kv(lines, "open_preview_tab", defaults.open_preview_tab)
	kv(lines, "scroll_sync", defaults.scroll_sync)
	local b = defaults.browser or {}
	kv(lines, "browser.open_mode", b.open_mode)
	kv(lines, "browser.theme", b.theme)
	kv(lines, "browser.browser_autostart", b.browser_autostart)
	kv(lines, "browser.require_display", b.require_display)

	section("Running session")
	local state = require("mdview.core.state")
	local running = state.proc_is_running()
	kv(lines, "server running", running)
	kv(lines, "state.get_server()", state.get_server() ~= nil)
	kv(lines, "attached", state.is_attached())
	kv(lines, "session token set", state.get_token() ~= nil)
	local port = vim.g.mdview_server_port or defaults.server_port
	kv(lines, "detected port", port)
	if running then
		kv(lines, "GET /health", curl_get(("http://127.0.0.1:%d/health"):format(port)))
	end

	section("Active transport (browser <-> relay)")
	local exp = defaults.experimental or {}
	kv(lines, "experimental.webtransport", exp.webtransport == true)
	-- The browser client reports its actual transport via /clientlog; scan the
	-- captured relay stdout for the most recent canonical "transport active:"
	-- line. Honest even when webtransport was requested: with no HTTP/3 backend
	-- it falls back and reports websocket.
	local ok_alog, alog = pcall(require, "mdview.adapter.log")
	local active = "(unknown — open a preview and check :MDViewShowWebLogs)"
	if ok_alog and type(alog.lines) == "function" then
		local llines = alog.lines()
		for i = #llines, 1, -1 do
			local m = tostring(llines[i]):match("transport active:%s*(%S+)")
			if m then
				active = m
				break
			end
		end
	end
	kv(lines, "client reports", active)
	if exp.webtransport == true and active == "websocket" then
		lines[#lines + 1] = "  note: webtransport is on but fell back to websocket (no HTTP/3 relay backend yet)"
	end

	section("Browser URL that would be opened")
	local ok_launcher, launcher = pcall(require, "mdview.bindings.usrcmds.start.server.launcher")
	if ok_launcher then
		local buf = vim.api.nvim_get_current_buf()
		local normalize = require("mdview.helper.normalize")
		local key = normalize.path(vim.api.nvim_buf_get_name(buf))
		local ok_url, url = pcall(launcher.resolve_browser_url, { key = key })
		kv(lines, "url", ok_url and url or ("(error: " .. tostring(url) .. ")"))
	end

	section("Recent internal log (mdview.log ring, newest last)")
	local ok_ring, ring = pcall(function()
		return require("mdview.log").snapshot()
	end)
	if ok_ring and ring and #ring > 0 then
		local start = math.max(1, #ring - 50)
		for i = start, #ring do
			local rec = ring[i]
			local msg = type(rec) == "table" and (rec.msg or vim.inspect(rec)) or tostring(rec)
			lines[#lines + 1] = "  " .. tostring(msg)
		end
	else
		lines[#lines + 1] = "  (no records)"
	end

	return lines
end

--- Run diagnostics, write the report to `path` (or a timestamped default in
--- stdpath('log')), and return the path.
---@param path string|nil
---@return string report_path
function M.run(path)
	local lines = M.collect()
	if not path or path == "" then
		local dir = fn.stdpath("log")
		pcall(fn.mkdir, dir, "p")
		path = dir .. "/mdview-diagnostics.txt"
	end
	local f = io.open(path, "w")
	if f then
		f:write(table.concat(lines, "\n") .. "\n")
		f:close()
	end
	return path
end

return M

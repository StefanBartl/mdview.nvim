---FIX: `uv`-LSP

---@module 'mdview.usercommands.autostart'
--- Autostart helper: start server and open preview. Integrates with mdview.adapter.browser when available.
--- Returns browser handle when it started a controllable browser instance, otherwise nil.

local runner = require("mdview.adapter.runner")
local browser_adapter = require("mdview.adapter.browser")
local api = vim.api
local fn = vim.fn
local uv = vim.loop
local notify = vim.notify

local M = {}

local SERVER_URL = "http://localhost:43219"
local HEALTH_ENDPOINT = SERVER_URL .. "/health"
local POLL_INTERVAL = 100 -- ms
local TIMEOUT_MS = 5000 -- ms

-- Toggle: whether to wait for server before opening preview
M.wait_for_ready = true

-- Open browser using the adapter fallback strategy: adapter returns handle or nil+err.
-- If adapter fails to produce a controllable handle, fall back to platform default opener without storing handle.
---@param url string
---@return table|nil handle, string|nil err
local function open_preview_browser(url)
	-- Try to use resolved browser command from config (adapter resolves automatically)
	local handle, err = browser_adapter.open(url)
	if handle then
		return handle, nil
	end

	-- fallback: use platform opener (not controllable)
	if fn.has("win32") == 1 then
		fn.jobstart({ "cmd", "/c", "start", "", url })
	elseif vim.fn.has("mac") == 1 then
		fn.jobstart({ "open", url })
	else
		fn.jobstart({ "xdg-open", url })
	end

	-- No handle to return; caller should not attempt to close
	return nil, err
end

-- Simple async health-check using curl or powershell fallback (kept minimal)
local function http_check(url, cb)
	local cmd
	if fn.has("win32") == 1 then
		cmd = {
			"powershell",
			"-Command",
			"try { (Invoke-WebRequest -Uri '" .. url .. "' -UseBasicParsing).Content } catch { '' }",
		}
	else
		cmd = { "sh", "-c", "curl -sS " .. url }
	end

	---@diagnostic disable-next-line
	local stdout = uv.new_pipe(false)
	---@diagnostic disable-next-line
	local stderr = uv.new_pipe(false)

	local handle
	---@diagnostic disable-next-line
	handle, _ = uv.spawn(cmd[1], {
		args = vim.list_slice(cmd, 2),
		stdio = { nil, stdout, stderr },
	}, function(_, _)
		if stdout then
			stdout:close()
		end
		if stderr then
			stderr:close()
		end
		if handle then
			handle:close()
		end
	end)

	local chunks = {}
	stdout:read_start(function(_, data)
		if data then
			table.insert(chunks, data)
		end
	end)
	stderr:read_start(function(_, _) end)

	-- wait briefly and call cb when data is received (simple)
	---@diagnostic disable-next-line
	local t = uv.new_timer()
	t:start(POLL_INTERVAL, 0, function()
		t:stop()
		t:close()
		if #chunks > 0 then
			cb(table.concat(chunks))
		else
			cb(nil)
		end
	end)
end

local function wait_for_server(cb)
	---@diagnostic disable-next-line
	local timer = uv.new_timer()
	---@diagnostic disable-next-line
	local start_time = uv.now()
	timer:start(0, POLL_INTERVAL, function()
		---@diagnostic disable-next-line
		if uv.now() - start_time > TIMEOUT_MS then
			timer:stop()
			timer:close()
			notify("[mdview] Server health-check timeout, opening preview anyway", vim.log.levels.WARN)
			cb(false)
			return
		end

		http_check(HEALTH_ENDPOINT, function(resp)
			if resp and resp:match("ok") then
				timer:stop()
				timer:close()
				cb(true)
			end
		end)
	end)
end

-- Open a simple scratch preview tab in Neovim (fallback)
---@diagnostic disable-next-line
local function open_preview_tab()
	local buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_name(buf, "mdview://preview")
	api.nvim_set_option_value("buftype", "nofile", { scope = "local", buf = buf })
	api.nvim_set_option_value("bufhidden", "wipe", { scope = "local", buf = buf })

	api.nvim_open_win(buf, true, {
		relative = "editor",
		width = math.floor(vim.o.columns * 0.8),
		height = math.floor(vim.o.lines * 0.8),
		row = math.floor(vim.o.lines * 0.1),
		col = math.floor(vim.o.columns * 0.1),
		style = "minimal",
		border = "single",
	})

	local html_lines = {
		"<html>",
		"<body>",
		"<iframe src='" .. SERVER_URL .. "' style='width:100%; height:100%; border:none'></iframe>",
		"</body>",
		"</html>",
	}
	api.nvim_buf_set_lines(buf, 0, -1, false, html_lines)
end

-- Main autostart function: starts server and opens browser/preview.
-- Returns browser handle if a controllable instance was started, otherwise nil.
-- @param wait boolean: whether to wait for health-check before opening preview
function M.start(wait)
	wait = (wait == nil) and M.wait_for_ready or wait

	-- ensure server is (re)started using runner
	if runner.is_running() then
		runner.stop_server(runner.proc)
	end
	runner.start_server("npm", { "run", "dev:server" })

	local function open_and_return_handle()
		notify("[mdview] Opening preview...", vim.log.levels.INFO)
		-- prefer opening the controllable browser instance
		local handle, err = open_preview_browser(SERVER_URL)
		if not handle and err then
			notify(("[mdview] browser adapter: %s"):format(tostring(err)), vim.log.levels.WARN)
		end
		return handle
	end

	if wait then
		wait_for_server(function(ok)
			if ok then
				notify("[mdview] Server ready, opening browser...", vim.log.levels.INFO)
			else
				notify("[mdview] Opening preview without successful health-check", vim.log.levels.INFO)
			end
		end)
		-- give some time and then open (non-blocking)
		---@diagnostic disable-next-line
		uv.new_timer():start(500, 0, function()
			---@diagnostic disable-next-line
			uv.new_timer():stop() -- noop to ensure timer created
		end)
	end

	-- open now (non-blocking) and return handle
	local handle = open_and_return_handle()

	-- ensure server process is stopped on VimLeavePre
	api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			if runner.is_running() then
				runner.stop_server(runner.proc)
			end
		end,
	})

	return handle
end

return M

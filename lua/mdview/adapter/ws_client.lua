---@module 'mdview.adapter.ws_client'
-- Enhanced wait_ready helper with robust logging, retries, and Windows support.

--AUDIT: Modularieseren

local fn = vim.fn
local uv = vim.loop
local api = vim.api
local normalize = require("mdview.helper.normalize")
local log = require("mdview.helper.log")

local M = {}

local DEFAULT_PORT = 43219
local HEALTH_POLL_MS = 200 -- polling interval
local HEALTH_TIMEOUT_MS = 10000 -- total wait time
local MAX_RETRIES = 5 -- number of retry attempts for a single message
local BASE_RETRY_MS = 150 -- initial retry delay (exponential backoff)
-- exported per-call wait timeout (used by live_push)
M.WAIT_READY_TIMEOUT = M.WAIT_READY_TIMEOUT or 2000

M.last_request = {}
M._pending = {} -- pending queue: path -> { markdown=..., tries=0 }
M._is_waiting = false

-- simple helper to construct /health URL
---@param port integer
---@return string
local function health_url(port)
	return string.format("http://localhost:%d/health", port)
end

local function ws_url()
  local port = vim.g.mdview_server_port or DEFAULT_PORT
  return "ws://localhost:" .. tostring(port) .. "/ws"
end


-- Non-blocking curl GET fallback
---@param url string
---@param cb fun(code:integer)
local function http_get(url, cb)
	local curl = fn.executable("curl") == 1 and "curl" or nil
	if curl then
		fn.jobstart({ curl, "-sS", url }, {
			stdout_buffered = true,
			stderr_buffered = true,
			on_exit = function(_, code, _)
				cb(code)
			end,
		})
	else
		-- fallback: blocking system call (Windows may fail if sh not available)
		local ok, _ = pcall(function()
			fn.system("curl -sS " .. url)
		end)
		cb(ok and 0 or 1)
	end
end

--- Wait until server responds on /health or timeout.
-- Enhanced for Windows/slow startup
---@param cb fun(ok:boolean)
---@param timeout_ms integer|nil
function M.wait_ready(cb, timeout_ms)
	cb = cb or function() end
	local timeout = timeout_ms or HEALTH_TIMEOUT_MS
	---@diagnostic disable-next-line LSP-Problems with lib.uv
	local start_time = uv.now()
	local attempt = 0

	local function poll()
		attempt = attempt + 1
		local port = vim.g.mdview_server_port or DEFAULT_PORT
		local url = health_url(port)

		http_get(url, function(code)
			if code == 0 then
				local msg =
					---@diagnostic disable-next-line LSP-Problems with uv.
					string.format("[mdview] server ready after %d ms, attempt %d\n", uv.now() - start_time, attempt)
				vim.api.nvim_echo({ { msg, "" } }, false, {})
			else
				---@diagnostic disable-next-line LSP-Problems with uv.
				if (uv.now() - start_time) < timeout then
					-- optionally log every N attempts
					if attempt % 10 == 0 then
						api.nvim_echo(
							{ { string.format("[mdview] waiting for server, attempt %d...\n", attempt), nil } },
							true,
							{}
						)
					end
					vim.defer_fn(poll, HEALTH_POLL_MS)
				else
					api.nvim_echo(
						{ { "[mdview] server health-check timed out after " .. tostring(timeout) .. "ms", "ErrorMsg" } },
						true,
						{ err = true }
					)
					cb(false)
				end
			end
		end)
	end

	poll()
end

-- internal helper: construct URL for /render
---@param path string # file path to render
---@return string # constructed URL pointing to the /render endpoint
local function render_url_for(path)
	local port = vim.g.mdview_server_port or DEFAULT_PORT
	local normalized = normalize.path_for_url(path)
	return string.format("http://localhost:%d/render?key=%s", port, normalized)
end

-- Collects stdout/stderr lines and returns them to the callback so caller
-- (try_send_pending) can log the server response body (and quickly detect empty replies).
-- Helper: execute an HTTP POST using curl via jobstart when available.
-- Callback signature: cb(exit_code:number, stdout_lines:string[]|nil, stderr_lines:string[]|nil)
---@param url URL # target URL for the POST request
---@param body string # request body content
---@param cb fun(exit_code: integer, stdout_lines: string[]|nil, stderr_lines: string[]|nil)? # optional callback invoked on completion
---@return integer|nil # job ID if curl jobstart was used, nil otherwise
local function http_post_nonblocking(url, body, cb)
	cb = cb or function() end
	local curl = fn.executable("curl") == 1 and "curl" or nil

	if curl then
		local tmpf = fn.tempname()
		local f = io.open(tmpf, "wb")
		if f then
			f:write(body)
			f:close()
		end

		local stdout_acc = {}
		local stderr_acc = {}

		local args = { "-sS", "-X", "POST", url, "--data-binary", "@" .. tmpf, "-H", "Content-Type: text/markdown" }
		local jid = fn.jobstart(vim.list_extend({ curl }, args), {
			stdout_buffered = true,
			stderr_buffered = true,
			on_stdout = function(_, data, _)
				if data and #data > 0 then
					for _, line in ipairs(data) do
						if line and line ~= "" then
							table.insert(stdout_acc, line)
						end
					end
				end
			end,
			on_stderr = function(_, data, _)
				if data and #data > 0 then
					for _, line in ipairs(data) do
						if line and line ~= "" then
							table.insert(stderr_acc, line)
						end
					end
				end
			end,
			on_exit = function(_, code, _)
				pcall(function()
					os.remove(tmpf)
				end)
				-- pass collected stdout/stderr to callback
				cb(code, (#stdout_acc > 0) and stdout_acc or nil, (#stderr_acc > 0) and stderr_acc or nil)
			end,
		})
		return jid
	else
		-- fallback: blocking call via system; capture output and forward it to cb
		local ok, res = pcall(function()
			-- portable shell invocation; on Windows this may fail if sh is not available
			local cmd = string.format(
				"sh -c %q",
				"curl -sS -X POST "
					.. url
					.. " -H 'Content-Type: text/markdown' --data-binary @- <<'BODY'\n"
					.. body
					.. "\nBODY"
			)
			return fn.system(cmd)
		end)
		if ok then
			-- res is a string; split into lines for parity with curl-on_exit
			local lines = {}
			if res and res ~= "" then
				for s in res:gmatch("([^\n]*)\n?") do
					if s ~= "" then
						table.insert(lines, s)
					end
				end
			end
			cb(0, (#lines > 0) and lines or nil, nil)
			return nil
		else
			cb(1, nil, { tostring(res) })
			return nil
		end
	end
end

-- Replace or augment try_send_pending callback handling to log response body.
---@param path string # file path whose pending markdown should be sent
local function try_send_pending(path)
	-- English comment: normalize incoming path and bail out if normalization fails
	local norm_path = normalize.path(path)
	if norm_path then
		path = norm_path
	else
		log.debug("[mdvview.ws_client] normalized path is nil", vim.log.levels.ERROR, "ws_client", true)
		return
	end

	local entry = M._pending[path]
	if not entry then
		return
	end
	entry.tries = (entry.tries or 0) + 1

	local url = ws_url()
	http_post_nonblocking(url, entry.markdown, function(code, stdout_lines, stderr_lines)
		if code == 0 then
			-- success: clear queue
			M._pending[path] = nil
			if stdout_lines and #stdout_lines > 0 then
				-- join and log first 2000 chars for brevity
				local body = table.concat(stdout_lines, "\n")
				local truncated = body:sub(1, 2000)

				-- schedule the UI writes to avoid calling UI APIs from a fast callback context
				vim.schedule(function()
					-- informational message
					api.nvim_echo(
						{ { "[mdview.ws_client] http_post_nonblocking success for " .. tostring(url), nil } },
						true,
						{}
					)
					-- response body (truncated)
					api.nvim_echo(
						{ { "[mdview.ws_client] response body (truncated 2k):\n" .. truncated, nil } },
						true,
						{}
					)
				end)
			else
				-- empty body: schedule the echo as well
				vim.schedule(function()
					api.nvim_echo({
						{
							"[mdview.ws_client] http_post_nonblocking success for " .. tostring(url) .. " (empty body)",
							nil,
						},
					}, true, {})
				end)
			end
		else
			-- failure: retry/backoff as before
			if stderr_lines and #stderr_lines > 0 then
				-- schedule error message to avoid fast-event restrictions
				vim.schedule(function()
					api.nvim_echo(
						{ { "[mdview.ws_client] http_post stderr: " .. table.concat(stderr_lines, "\n"), "ErrorMsg" } },
						true,
						{ err = true }
					)
				end)
			end
			if entry.tries < (entry.max_retries or MAX_RETRIES) then
				local delay = (BASE_RETRY_MS * (2 ^ (entry.tries - 1)))
				vim.defer_fn(function()
					try_send_pending(path)
				end, delay)
			else
				M._pending[path] = nil
				-- schedule final failure notification
				vim.schedule(function()
					api.nvim_echo({
						{
							"[mdview.ws_client] failed to send markdown for "
								.. tostring(path)
								.. " after "
								.. tostring(entry.tries)
								.. " attempts",
							"ErrorMsg",
						},
					}, true, { err = true })
				end)
			end
		end
	end)
end

-- Public: send markdown to server.
-- Non-blocking; retries on failure with exponential backoff.
-- @param path string absolute file path (used as key)
-- @param markdown string file content
-- @param opts table|nil { max_retries?: integer, immediate?: boolean }
function M.send_markdown(path, markdown, opts)
	opts = opts or {}
	if type(path) ~= "string" or type(markdown) ~= "string" then
		return
	end

	-- In send_markdown, where opts.immediate branch posts directly, add logging of stdout.
	if opts.immediate then
		http_post_nonblocking(render_url_for(path), markdown, function(code, stdout_lines, stderr_lines)
			if code == 0 then
				if stdout_lines and #stdout_lines > 0 then
					local body = table.concat(stdout_lines, "\n")
					api.nvim_echo(
						{ { "[mdview.ws_client] immediate post success for " .. render_url_for(path), nil } },
						true,
						{}
					)
					api.nvim_echo(
						{ { "[mdview.ws_client] immediate response (truncated 2k):\n" .. body:sub(1, 2000), nil } },
						true,
						{}
					)
				else
					api.nvim_echo({ { "[mdview.ws_client] immediate post success (empty body)", nil } }, true, {})
				end
			else
				if stderr_lines and #stderr_lines > 0 then
					api.nvim_echo({
						{
							"[mdview.ws_client] immediate post stderr: " .. table.concat(stderr_lines, "\n"),
							"ErrorMsg",
						},
					}, true, {})
				else
					api.nvim_echo({ { "[mdview.ws_client] immediate post failed for " .. path, "ErrorMsg" } }, true, {})
				end
			end
		end)
		return
	end

	-- Coalesce rapid updates in _pending queue
	M._pending[path] = {
		markdown = markdown,
		tries = 0,
		max_retries = opts.max_retries or MAX_RETRIES,
	}

	try_send_pending(path)
end

return M

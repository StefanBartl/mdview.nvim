---@module 'mdview.adapter.ws_client'
-- Enhanced wait_ready helper with robust logging, retries, and Windows support.
-- Reviewed for a further file split ("Modularisieren"): the four concerns
-- here (health polling, URL building, HTTP transport, retry/queue) are each
-- already a single named local function with a clear boundary: splitting
-- them into separate files would add cross-file indirection without a
-- corresponding win, unlike e.g. bindings/ or adapter/browser/, which
-- separate genuinely independent, independently-testable, multi-consumer
-- concerns. Kept as one file.

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

-- Once the server has answered /health once, remember it so subsequent
-- wait_ready calls (live_push wraps EVERY TextChanged in one) short-circuit
-- instead of doing a curl /health round trip per keystroke. Reset whenever
-- the server process is (re)spawned or stopped (launcher.start / stop.stop).
M._ready = false

function M.reset_ready()
	M._ready = false
end

-- simple helper to construct /health URL
---@param port integer
---@return string
local function health_url(port)
	return string.format("http://localhost:%d/health", port)
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

--- Wait until server responds on /health or timeout, then call cb(true) /
--- cb(false). Once the server has been seen healthy, later calls short-circuit
--- to cb(true) without another /health round trip (see M.reset_ready).
---@param cb fun(ok:boolean)
---@param timeout_ms integer|nil
function M.wait_ready(cb, timeout_ms)
	cb = cb or function() end

	if M._ready then
		cb(true)
		return
	end

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
				M._ready = true
				log.debug(
					---@diagnostic disable-next-line LSP-Problems with uv.
					string.format("server ready after %d ms, attempt %d", uv.now() - start_time, attempt),
					nil,
					"ws_client",
					true
				)
				cb(true)
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

-- internal helper: construct a URL for an mdview-server endpoint,
-- authenticated with the shared session token generated for the currently
-- running process.
---@param endpoint string # e.g. "update" or "scroll"
---@param path string # file path being previewed (used as the room key)
---@return string
local function endpoint_url_for(endpoint, path)
	local port = vim.g.mdview_server_port or DEFAULT_PORT
	local normalized = normalize.path_for_url(path)
	local token = require("mdview.core.state").get_token() or ""
	return string.format(
		"http://localhost:%d/%s?key=%s&token=%s",
		port,
		endpoint,
		normalized,
		vim.uri_encode(token)
	)
end

---@param path string
---@return string
local function update_url_for(path)
	return endpoint_url_for("update", path)
end

---@param path string
---@return string
local function scroll_url_for(path)
	return endpoint_url_for("scroll", path)
end

---@param path string
---@return string
local function diff_url_for(path)
	return endpoint_url_for("diff", path)
end

---@param path string
---@return string
local function doc_url_for(path)
	return endpoint_url_for("doc", path)
end

---@param path string
---@return string
local function control_url_for(path)
	return endpoint_url_for("control", path)
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

	local url = update_url_for(path)
	http_post_nonblocking(url, entry.markdown, function(code, stdout_lines, stderr_lines)
		if code == 0 then
			-- success: clear queue
			M._pending[path] = nil
			vim.schedule(function()
				local body = stdout_lines and table.concat(stdout_lines, "\n"):sub(1, 200) or "(empty body)"
				log.debug("queued post success for " .. tostring(url) .. " -> " .. body, nil, "ws_client", true)
			end)
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

	if opts.immediate then
		http_post_nonblocking(update_url_for(path), markdown, function(code, stdout_lines, stderr_lines)
			if code == 0 then
				vim.schedule(function()
					local body = stdout_lines and table.concat(stdout_lines, "\n"):sub(1, 200) or "(empty body)"
					log.debug("immediate post success -> " .. body, nil, "ws_client", true)
				end)
			else
				vim.schedule(function()
					if stderr_lines and #stderr_lines > 0 then
						api.nvim_echo({
							{
								"[mdview.ws_client] immediate post stderr: " .. table.concat(stderr_lines, "\n"),
								"ErrorMsg",
							},
						}, true, {})
					else
						api.nvim_echo(
							{ { "[mdview.ws_client] immediate post failed for " .. path, "ErrorMsg" } },
							true,
							{}
						)
					end
				end)
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

-- Public: send the current cursor line + total line count for `path`'s
-- preview, so the browser tab can scroll to follow (nvim-to-browser half of
-- bidirectional scrolling). Fire-and-forget — no retry queue, since a scroll
-- position is a frequently-superseded transient signal, not durable content;
-- if one ping is lost the next cursor move corrects it.
---@param path string
---@param line integer # 1-based current cursor line
---@param total integer # total line count in the buffer
---@param viewfrac number|nil # desired 0..1 vertical position of the line in the browser viewport
---@param col integer|nil # 0-based byte column of the cursor (for the cursor caret)
function M.send_scroll(path, line, total, viewfrac, col)
	if type(path) ~= "string" or path == "" then
		return
	end
	local body = tostring(line) .. "/" .. tostring(total)
	-- col rides in the 4th field, which requires the 3rd (viewfrac) to be
	-- present as a placeholder so positions line up on the client.
	if type(viewfrac) == "number" then
		body = body .. "/" .. ("%.4f"):format(viewfrac)
	elseif type(col) == "number" then
		body = body .. "/0"
	end
	if type(col) == "number" then
		body = body .. "/" .. tostring(col)
	end
	http_post_nonblocking(scroll_url_for(path), body, function() end)
end

-- ---------------------------------------------------------------------------
-- Opt-in line-diff transport (experimental.line_diff). Full snapshots go via
-- /update (stored as the relay's LastPayload so late-joiners get whole text);
-- incremental diffs go via /diff (ephemeral). Both are \x03-tagged JSON
-- envelopes carrying a monotonic version so the client (src/client/render/
-- diffDoc.ts) can apply diffs in order and resync from a full on any mismatch.
-- ---------------------------------------------------------------------------

-- Force a full snapshot at least this often so a client that dropped/reordered
-- a diff (and desynced) self-heals within a bounded number of edits.
local FULL_EVERY = 25

-- Per room-key transport state for the diff path.
M._diff_ver = {} -- last version number sent for a key
M._diff_last = {} -- last full line array sent for a key (diff basis)
M._diff_since = {} -- diffs sent since the last full for a key

--- Reset the diff-transport bookkeeping for one key (or all when key is nil),
--- so the next send for it starts with a fresh full snapshot. Called on stop
--- and whenever the previewed document changes rooms.
---@param key string|nil
---@return nil
function M.reset_diff_state(key)
	if key then
		M._diff_ver[key] = nil
		M._diff_last[key] = nil
		M._diff_since[key] = nil
	else
		M._diff_ver = {}
		M._diff_last = {}
		M._diff_since = {}
	end
end

---@return boolean
local function line_diff_enabled()
	local ok, exp = pcall(function()
		return require("mdview.config").defaults.experimental
	end)
	return ok and type(exp) == "table" and exp.line_diff == true
end

-- Public: send the current content of `key`'s room as `lines`. With
-- experimental.line_diff off this is a plain full-text push (unchanged wire
-- format). With it on, sends a versioned full snapshot when needed (first send,
-- forced, or every FULL_EVERY edits) and a minimal line diff otherwise.
---@param key string # room key (normalized path)
---@param lines string[] # current buffer lines
---@param opts { full?: boolean }|nil
---@return nil
function M.send_content(key, lines, opts)
	opts = opts or {}
	if type(key) ~= "string" or key == "" then
		return
	end
	lines = lines or {}

	if not line_diff_enabled() then
		-- legacy path: push the whole document as raw text (unchanged wire format)
		M.send_markdown(key, table.concat(lines, "\n"), { immediate = true })
		return
	end

	local ver = M._diff_ver[key]
	local last = M._diff_last[key]
	local since = M._diff_since[key] or 0
	local force_full = opts.full == true or ver == nil or last == nil or since >= FULL_EVERY

	if force_full then
		local nv = (ver or 0) + 1
		local env = "\3" .. vim.json.encode({ t = "f", v = nv, text = table.concat(lines, "\n") })
		M.send_markdown(key, env, { immediate = true }) -- via /update -> LastPayload
		M._diff_ver[key] = nv
		M._diff_last[key] = lines
		M._diff_since[key] = 0
		return
	end

	local edit = require("mdview.utils.line_diff")(last, lines)
	if not edit then
		return -- no change
	end
	local nv = ver + 1
	local env = "\3" .. vim.json.encode({ t = "d", v = nv, base = ver, edits = { edit } })
	http_post_nonblocking(diff_url_for(key), env, function() end) -- via /diff (ephemeral)
	M._diff_ver[key] = nv
	M._diff_last[key] = lines
	M._diff_since[key] = since + 1
end

-- Public: tell the preview tab(s) of `key`'s room which document is now shown
-- (`doc_path`), so the client can maintain browser history for Back/Forward.
-- Fire-and-forget; sent only when the previewed document actually changes.
---@param key string # room key the tab watches
---@param doc_path string # absolute path of the now-previewed document
---@return nil
function M.send_doc(key, doc_path)
	if type(key) ~= "string" or key == "" or type(doc_path) ~= "string" or doc_path == "" then
		return
	end
	http_post_nonblocking(doc_url_for(key), doc_path, function() end)
end

-- Public: push a live preview-control update (a small JSON string, e.g.
-- '{"cursor":"caret"}' or '{"zoom":1.2}') to `key`'s room, so runtime commands
-- change the open tab without a reload. Fire-and-forget — a control update is a
-- transient signal; if one is lost the next command (or a reopen with the URL
-- params) corrects it.
---@param key string # room key the tab watches
---@param json string # a small JSON control object
---@return nil
function M.send_control(key, json)
	if type(key) ~= "string" or key == "" or type(json) ~= "string" or json == "" then
		return
	end
	http_post_nonblocking(control_url_for(key), json, function() end)
end

-- Public: ask every connected preview tab to close itself (the relay
-- broadcasts a close signal to all rooms; the client calls window.close()).
-- Used by :MDViewStop so tabs opened in the OS default browser — which mdview
-- can't close via a process handle — close cooperatively.
--
-- Intentionally BLOCKING with a short timeout: it runs right before the relay
-- process is killed, so a fire-and-forget POST would race the shutdown and
-- usually lose. A brief synchronous curl guarantees the relay broadcasts the
-- signal before it dies. Best-effort — any failure is swallowed (the tab just
-- stays open, exactly as it did before this feature).
---@return nil
function M.send_close()
	if fn.executable("curl") ~= 1 then
		return
	end
	local port = vim.g.mdview_server_port or DEFAULT_PORT
	local token = require("mdview.core.state").get_token() or ""
	local url = string.format("http://localhost:%d/close?token=%s", port, vim.uri_encode(token))
	pcall(fn.system, { "curl", "-sS", "--max-time", "1", "-X", "POST", url })
end

return M

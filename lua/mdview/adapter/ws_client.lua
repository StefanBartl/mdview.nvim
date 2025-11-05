---@module 'mdview.adapter.ws_client'
--- Minimal WebSocket/HTTP client helper to send markdown to the local server.
--- Adds an internal send-queue with retry/backoff and a simple wait_ready() helper
--- so callers can wait until the HTTP server becomes reachable before sending.

---@diagnostic disable: redundant-parameter, undefined-field, deprecated, unused-local, empty-block, undefined-global, return-type-mismatch

local fn = vim.fn
local api = vim.api
local uv = vim.loop

local M = {}

local DEFAULT_PORT = 43219
local MAX_RETRIES = 5          -- number of retry attempts for a single message
local BASE_RETRY_MS = 150      -- initial retry delay (exponential backoff)
local HEALTH_POLL_MS = 200     -- polling interval for wait_ready
local HEALTH_TIMEOUT_MS = 5000 -- overall timeout for wait_ready

M.last_request = {}
M._pending = {}                -- pending queue: path -> { markdown=..., tries=0 }
M._is_waiting = false

-- Helper: execute an HTTP POST using curl via jobstart when available.
-- Callback signature: cb(exit_code:number, stdout_lines:string[]|nil, stderr_lines:string[]|nil)
---@param url string # target URL for the POST request
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

    local args = { "-sS", "-X", "POST", url, "--data-binary", "@" .. tmpf, "-H", "Content-Type: text/markdown" }
    local jid = fn.jobstart(vim.list_extend({ curl }, args), {
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data, _)
        -- noop; forward on exit
      end,
      on_stderr = function(_, data, _)
        -- noop; forward on exit
      end,
      on_exit = function(_, code, _)
        -- read captured output
        pcall(function() os.remove(tmpf) end)
        cb(code, nil, nil)
      end,
    })
    return jid
  else
    -- fallback: blocking call via system
    local ok, res = pcall(function()
      -- try portable shell invocation; on Windows this may fail if sh not available
      local cmd = string.format("sh -c %q", "curl -sS -X POST " .. url .. " -H 'Content-Type: text/markdown' --data-binary @- <<'BODY'\n" .. body .. "\nBODY")
      return fn.system(cmd)
    end)
    if ok then
      cb(0, res and { res } or nil, nil)
      return nil
    else
      cb(1, nil, { tostring(res) })
      return nil
    end
  end
end

-- Simple HTTP GET for health check (non-blocking using curl if available).
---@param url string # target URL for the GET request
---@param cb fun(exit_code: integer, stdout_lines: string[]|nil, stderr_lines: string[]|nil)? # optional callback invoked on completion
---@return integer|nil # job ID if curl jobstart was used, nil otherwise
local function http_get_nonblocking(url, cb)
  cb = cb or function() end
  local curl = fn.executable("curl") == 1 and "curl" or nil
  if curl then
    local jid = fn.jobstart({ curl, "-sS", url }, {
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data, _)
        -- on success pass code 0 and data array
        if data and #data > 0 then
          cb(0, data, nil)
        else
          cb(0, {}, nil)
        end
      end,
      on_stderr = function(_, data, _)
        if data and #data > 0 then
          cb(1, nil, data)
        end
      end,
      on_exit = function(_, code, _)
        -- nothing to do here because callbacks were called above
      end,
    })
    return jid
  else
    -- fallback blocking
    local ok, res = pcall(function() return fn.system("curl -sS " .. url) end)
    if ok then
      cb(0, { res }, nil)
    else
      cb(1, nil, { tostring(res) })
    end
    return nil
  end
end

-- internal helper: construct URL for /render
---@param path string # file path to render
---@return string # constructed URL pointing to the /render endpoint
local function render_url_for(path)
  local port = vim.g.mdview_server_port or DEFAULT_PORT
  return string.format("http://localhost:%d/render?key=%s", port, fn.fnameescape(path))
end

-- Try to send a single pending entry. Handles retries and eventual give-up.
---@param path string # file path whose pending markdown should be sent
local function try_send_pending(path)
  local entry = M._pending[path]
  if not entry then return end
  entry.tries = (entry.tries or 0) + 1

  local url = render_url_for(path)
  http_post_nonblocking(url, entry.markdown, function(code, _, stderr)
    if code == 0 then
      -- success: clear queue
      M._pending[path] = nil
    else
      if entry.tries < (entry.max_retries or MAX_RETRIES) then
        local delay = (BASE_RETRY_MS * (2 ^ (entry.tries - 1)))
        vim.defer_fn(function() try_send_pending(path) end, delay)
      else
        -- give up: expose a message (non-fatal)
        M._pending[path] = nil
        vim.schedule(function()
          api.nvim_err_writeln("[mdview.ws_client] failed to send markdown for " .. tostring(path) .. " after " .. tostring(entry.tries) .. " attempts")
        end)
      end
    end
  end)
end

-- Public: send markdown to server. This enqueues the payload and attempts an immediate send.
-- Non-blocking; automatically retries on failure with exponential backoff.
---@param path string absolute file path (used as key)
---@param markdown string file content
---@param opts { max_retries?: integer }|nil # optional overrides for retry behavior
function M.send_markdown(path, markdown, opts)
  opts = opts or {}
  if type(path) ~= "string" or type(markdown) ~= "string" then return end

  -- coalesce rapid updates by replacing pending payload
  M._pending[path] = {
    markdown = markdown,
    tries = 0,
    max_retries = opts.max_retries or MAX_RETRIES,
  }

  -- attempt immediate send
  try_send_pending(path)
end

---@param path string absolute file path (used as key)
---@param diffs table[] list of edit objects { op="replace"|"insert"|"delete", start=number, count=number, lines=string[]? }
---@param opts table|nil optional overrides
function M.send_patch(path, diffs, opts)
  opts = opts or {}
  if type(path) ~= "string" or type(diffs) ~= "table" then return end

  -- Build JSON payload
  local payload = {
    type = "patch",
    file = path,
    edits = diffs,
  }

  local json = vim.fn.json_encode(payload)

  -- Use internal helper to post JSON (re-use http_post_nonblocking or create one)
  -- We'll post to /render?key=<escaped_path>&patch=1 (server must support this)
  local port = vim.g.mdview_server_port or DEFAULT_PORT
  local url = string.format("http://localhost:%d/render?key=%s&patch=1", port, fn.fnameescape(path))

  -- Use the existing http_post_nonblocking (adapted to accept body + content-type)
  -- If http_post_nonblocking in module doesn't support content-type, add a small wrapper here
  local function post_json_nonblocking(_url, body, cb)
    cb = cb or function() end
    local curl = fn.executable("curl") == 1 and "curl" or nil
    if curl then
      local tmpf = fn.tempname()
      local f = io.open(tmpf, "wb")
      if f then
        f:write(body)
        f:close()
      end
      local args = { "-sS", "-X", "POST", _url, "--data-binary", "@" .. tmpf, "-H", "Content-Type: application/json" }
      fn.jobstart(vim.list_extend({ curl }, args), {
        stdout_buffered = true,
        stderr_buffered = true,
        on_exit = function(_, code, _)
          pcall(function() os.remove(tmpf) end)
          cb(code)
        end,
      })
    else
      -- fallback (blocking)
      local ok, res = pcall(function()
        local cmd = string.format("sh -c %q", "curl -sS -X POST " .. _url .. " -H 'Content-Type: application/json' --data-binary @- <<'BODY'\n" .. body .. "\nBODY")
        return fn.system(cmd)
      end)
      if ok then cb(0) else cb(1) end
    end
  end

  -- enqueue / attempt send (no retries here; reuse your try_send_pending pattern if desired)
  post_json_nonblocking(url, json, function(code)
    if code == 0 then
      -- success -> nothing to do (or update internal state)
    else
      vim.schedule(function()
        vim.notify(("mdview: failed to post patch for %s (code %s)"):format(path, tostring(code)), vim.log.levels.WARN)
      end)
    end
  end)
end

-- Wait until server health endpoint responds (or timeout).
-- Calls cb(ok:boolean) when ready or false on timeout.
---@param cb fun(ok: boolean) # callback invoked when server is ready or timeout occurs
---@param timeout_ms integer|nil # optional timeout in milliseconds (default HEALTH_TIMEOUT_MS)
function M.wait_ready(cb, timeout_ms)
  cb = cb or function() end
  local timeout = timeout_ms or HEALTH_TIMEOUT_MS
  local start = vim.loop.now()

  local function poll()
    local port = vim.g.mdview_server_port or DEFAULT_PORT
    local url = string.format("http://localhost:%d/health", port)
    http_get_nonblocking(url, function(code, _, _)
      if code == 0 then
        -- server responded
        cb(true)
      else
        if (vim.loop.now() - start) < timeout then
          vim.defer_fn(poll, HEALTH_POLL_MS)
        else
          cb(false)
        end
      end
    end)
  end

  poll()
end

return M

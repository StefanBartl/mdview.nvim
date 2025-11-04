---@module 'mdview.adapter.ws_client'
--- Minimal WebSocket client helper to send markdown to the local server.
--- Uses `curl` via jobstart as a portable fallback when no Lua websocket lib is present.
--- Sends full markdown payload on BufWritePost. Diffing is planned for future updates.

-- Disable specific diagnostics that complain about luv/vim.fn signatures and
-- environment-specific globals. This keeps LSP noise low while preserving real checks.
---@diagnostic disable: redundant-parameter, undefined-field, deprecated, unused-local, empty-block, undefined-global, return-type-mismatch

local fn = vim.fn
local api = vim.api
local M = {}
M.last_request = {}

-- Helper to execute an HTTP POST using curl installed on system.
-- Falls back to a shell+curl call via vim.fn.system if curl is missing.
-- English comments in code as required by project rules.

---@param url string
---@param body string
---@param cb function|nil callback receives (exit_code:number, res:string|nil)
local function http_post(url, body, cb)
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
      on_stdout = function(_, data, _)
        -- data is an array of lines; nothing required for POC
        if data and #data > 0 then
          -- optional: could aggregate/parse response here
        end
      end,
      on_stderr = function(_, data, _)
        if data and #data > 0 then
          api.nvim_err_writeln("[mdview][http_post] " .. table.concat(data, "\n"))
        end
      end,
      on_exit = function(_, code, _)
        -- cleanup temp file
        pcall(function() os.remove(tmpf) end)
        cb(code, nil)
      end,
    })
    return jid
  else
    -- fallback: use vim.fn.system() (blocking) - portable across shells
    local ok = pcall(function()
      -- Use a simple heredoc via sh -c; this may not be available on Windows shells.
      -- For Windows users, ensure curl is installed or adapt this branch.
      local cmd = string.format("sh -c %q", "cat <<'EOF' | curl -sS -X POST " .. url .. " -H 'Content-Type: text/markdown' --data-binary @- <<'BODY'\n" .. body .. "\nBODY")
      local res = fn.system(cmd)
      cb(0, res)
    end)
    if not ok then
      cb(1, nil)
    end
    return nil
  end
end

--- Send full markdown to server render endpoint.
---@param path string absolute file path (used as key)
---@param markdown string file content
function M.send_markdown(path, markdown)
  -- rate-limit: avoid hammering when many writes occur in quick succession
  local now = vim.loop.now and vim.loop.now() or vim.loop.hrtime and math.floor(vim.loop.hrtime() / 1e6) or 0
  local last = M.last_request[path] or 0
  if last > 0 and (now - last) < 100 then
    -- too frequent; coalesce: schedule delayed send (fire-and-forget)
    vim.defer_fn(function()
      M.send_markdown(path, markdown)
    end, 150)
    return
  end
  M.last_request[path] = now

  local port = vim.g.mdview_server_port or 43219
  local url = string.format("http://localhost:%d/render?key=%s", port, fn.fnameescape(path))

  -- non-blocking post
  pcall(function()
    http_post(url, markdown, function(code)
      if code ~= 0 then
        api.nvim_err_writeln("mdview: http post failed for " .. path)
      end
    end)
  end)
end

return M

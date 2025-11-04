---@module 'mdview.core.events'
--- Autocommand management for mdview.nvim.
--- Attaches BufEnter and BufWritePost to trigger server-render actions.

local api = vim.api
local session = require("mdview.core.session")
local ws_client = require("mdview.adapter.ws_client")
local config = require("mdview.config").defaults

local M = {}
M.augroup = nil

--- Internal handler for BufEnter: record buffer content snapshot.
---@param bufnr integer
local function on_buf_enter(bufnr)
  local ft = api.nvim_buf_get_option(bufnr, "filetype")
  if ft ~= "markdown" and ft ~= "md" then
    return
  end

  local path = api.nvim_buf_get_name(bufnr)
  if path == "" then
    return
  end

  -- capture current buffer lines and store snapshot
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  session.store(path, lines)
end

--- Internal handler for BufWritePost: send file (or diffs) to server.
---@param bufnr integer
local function on_buf_write(bufnr)
  local ft = api.nvim_buf_get_option(bufnr, "filetype") or ""
  if ft ~= "markdown" and ft ~= "md" then
    return
  end

  local path = api.nvim_buf_get_name(bufnr)
  if path == "" then
    return
  end

  -- read the new buffer content
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local prev = session.get(path)
  local diffs = session.compute_line_diff(prev and prev.lines or nil, lines)

  -- TODO: if config.send_diffs is true, send diffs. For now send full content for compatibility.
  local payload = table.concat(lines, "\n")

  -- send via ws_client (non-blocking)
  pcall(function()
    ws_client.send_markdown(path, payload)
  end)

  -- update snapshot
  session.store(path, lines)
end

--- Attach autocommands (Idempotent)
function M.attach()
  if M.augroup then
    return
  end
  M.augroup = api.nvim_create_augroup("MdviewAutocmds", { clear = true })

  -- BufEnter: capture snapshot
  api.nvim_create_autocmd({ "BufEnter" }, {
    group = M.augroup,
    callback = function(args)
      on_buf_enter(args.buf)
    end,
  })

  -- BufWritePost: send current file or diffs
  api.nvim_create_autocmd({ "BufWritePost" }, {
    group = M.augroup,
    callback = function(args)
      on_buf_write(args.buf)
    end,
  })
end

--- Detach autocommands and clear group
function M.detach()
  if not M.augroup then
    return
  end
  pcall(api.nvim_del_augroup_by_id, M.augroup)
  M.augroup = nil
end

return M

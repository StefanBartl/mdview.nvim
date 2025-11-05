---@module 'mdview.core.events'
-- Autocommand management for mdview.nvim.
-- Attaches BufEnter and BufWritePost to trigger server-render actions.

local session = require("mdview.core.session")
local ws_client = require("mdview.adapter.ws_client")
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")

local api = vim.api
local nvim_buf_get_name = api.nvim_buf_get_name
local nvim_create_autocmd = api.nvim_create_autocmd

local M = {}

M.augroup = nil

-- Internal handler for BufEnter: record buffer content snapshot.
---@param bufnr integer
local function on_buf_enter(bufnr)
	local ft = safe_buf_get_option(bufnr, "filetype")
	if ft ~= "markdown" and ft ~= "md" then
		return
	end

	local path = nvim_buf_get_name(bufnr)
	if path == "" then
		return
	end

	local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	session.store(path, lines)
end

-- Internal handler for BufWritePost: send file (or diffs) to server.
---@param bufnr integer
local function on_buf_write(bufnr)
  local ft = safe_buf_get_option(bufnr, "filetype") or ""
  if ft ~= "markdown" and ft ~= "md" then
    return
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
  local prev = session.get(path)
  local old_lines = (prev and prev.lines) or {}
  local new_lines = lines

  -- nil-safe check inside tables
  for i = 1, #old_lines do if old_lines[i] == nil then old_lines[i] = "" end end
  for i = 1, #new_lines do if new_lines[i] == nil then new_lines[i] = "" end end

  local diff = require("mdview.utils.diff_granular")
  local diffs = diff(old_lines, new_lines)

  -- Push each diff chunk immediately to the WS client
  for _, d in ipairs(diffs) do
    local chunk_lines = {}
    if d.op == "replace" then
      -- slice new_lines for the range
      chunk_lines = vim.list_slice(new_lines, d.start + 1, d.start + (d.count or #new_lines))
    elseif d.op == "insert" then
      chunk_lines = d.lines or {}
    elseif d.op == "delete" then
      -- send empty payload for deletes
      chunk_lines = {}
    end

    local payload = table.concat(chunk_lines, "\n")
    ws_client.send_markdown(path, payload)
  end

  -- Store current buffer state for next diff
  session.store(path, lines)
end

-- Attach autocommands
---@return nil
function M.attach()
	if M.augroup then
		return
	end
	M.augroup = api.nvim_create_augroup("MdviewAutocmds", { clear = true })

	nvim_create_autocmd({ "BufEnter" }, {
		group = M.augroup,
		desc = "[mdview] Capture buffer snapshot on enter",
		callback = function(args)
			on_buf_enter(args.buf)
		end,
	})

	nvim_create_autocmd({ "BufWritePost" }, {
		group = M.augroup,
		desc = "[mdview] Send current file or diffs on write",
		callback = function(args)
			on_buf_write(args.buf)
		end,
	})
end

-- Detach autocommands and clear group
---@return nil
function M.detach()
	if not M.augroup then
		return
	end
	pcall(api.nvim_del_augroup_by_id, M.augroup)
	M.augroup = nil
end

return M

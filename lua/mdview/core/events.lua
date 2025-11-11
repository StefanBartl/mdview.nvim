---@module 'mdview.core.events'
-- Autocommand management for mdview.nvim.
-- Handles initial push, BufWritePost, and BufEnter snapshots safely.

local session = require("mdview.core.session")
local ws_client = require("mdview.adapter.ws_client")
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")
local copy_lines = require("mdview.helper.copy_lines")
local normalize = require("mdview.helper.normalize")
local log = require("mdview.helper.log")
local diff_util = require("mdview.utils.diff_granular")

local api = vim.api
local nvim_buf_get_name = api.nvim_buf_get_name

local M = {}

-- Push buffer content to server, optionally forcing full buffer
---@param bufnr integer
---@param force boolean|nil
function M.push_buffer(bufnr, force)
	local ft = safe_buf_get_option(bufnr, "filetype") or ""
	if ft ~= "markdown" and ft ~= "md" then
		return
	end

	local path = nvim_buf_get_name(bufnr)
	if path == "" then
		return
	end
	local norm_path = normalize.path(path)
	if norm_path then
		path = norm_path
	else
		log.debug("normalized path ist nil", vim.log.levels.ERROR, "events", true)
		return
	end

	local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
	local prev = session.get(path)
	local old_lines = (prev and prev.lines) or {}
	local new_lines = lines

	for i = 1, #old_lines do
		if old_lines[i] == nil then
			old_lines[i] = ""
		end
	end
	for i = 1, #new_lines do
		if new_lines[i] == nil then
			new_lines[i] = ""
		end
	end

	local diffs
	if force or not prev then
		diffs = { { op = "replace", start = 0, count = #new_lines } }
	else
		diffs = diff_util(old_lines, new_lines)
	end

	log.debug(string.format("push_buffer diffs for %s: %d changes", path, #diffs), nil, "push", true)

	for _, d in ipairs(diffs) do
		local chunk_lines = {}
		if d.op == "replace" or d.op == "insert" then
			chunk_lines = vim.list_slice(new_lines, d.start + 1, d.start + (d.count or #new_lines))
		end
		local payload = table.concat(chunk_lines, "\n")
ws_client.send_markdown(path, payload, { immediate = (force == true) })
		log.debug(string.format("Sent chunk op=%s lines=%d for %s", d.op, #chunk_lines, path), nil, "push", true)
	end

	session.store(path, lines)
end

-- AUDIT: Unused so far
--- Snapshot helper used on BufEnter (no autocmds here).
---@param bufnr integer
function M.store_snapshot_on_enter(bufnr)
  local ft = safe_buf_get_option(bufnr, "filetype") or ""
  if ft ~= "markdown" and ft ~= "md" then return end

  local path = nvim_buf_get_name(bufnr)
  if path == "" then return end

  local norm_path = normalize.path(path)
  if not norm_path then
    log.debug("normalized path ist nil", vim.log.levels.ERROR, "events", true)
    return
  end
  path = norm_path

  if not session.get(path) then
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    session.store(path, copy_lines(lines))
    log.debug("BufEnter snapshot stored for path: " .. path, nil, "bufenter", true)
  end

end
return M

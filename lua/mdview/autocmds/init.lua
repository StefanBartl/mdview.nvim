---@module 'mdview.autocmds'
-- Centralized autocommand setup for mdview.nvim.
-- Optional modules (on_text_change, bufwrite) are kept for reference/debug.

local api = vim.api
local live_push = require("mdview.autocmds.live_push")
local bufenter = require("mdview.autocmds.bufenter")
local vim_leave = require("mdview.autocmds.vim_leave")
-- local on_text_change = require("mdview.autocmds.on_text_change")
-- local bufwrite = require("mdview.autocmds.bufwrite")
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}
M.augroup_id = nil

--- Detach and remove augroup
function M.teardown()
  if not M.augroup_id then return end
	autocmd_registry.detach_all()
  pcall(api.nvim_del_augroup_by_id, M.augroup_id)
  M.augroup_id = nil
end

--- Attach all autocommands in a single augroup
function M.attach()
  if M.augroup_id then
    return
  end

  M.augroup_id = api.nvim_create_augroup("MdviewAutocmds", { clear = true })

	bufenter.attach(M.augroup_id)  -- BufEnter snapshot
  live_push.attach(M.augroup_id) -- Live Markdown push (diffs + full push on write)
  vim_leave.attach(M.augroup_id) -- Stop server on VimLeave

  -- optional debug/legacy modules
  -- on_text_change.attach(M.augroup_id)
  -- bufwrite.attach(M.augroup_id)
end

return M

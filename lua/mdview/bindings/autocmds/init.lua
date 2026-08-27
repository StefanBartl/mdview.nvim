---@module 'mdview.bindings.autocmds'
-- Centralized autocommand setup for mdview.nvim.
-- Optional modules (on_text_change, bufwrite) are kept for reference/debug.

local api = vim.api
local live_push = require("mdview.bindings.autocmds.live_push")
local bufenter = require("mdview.bindings.autocmds.bufenter")
local buffer_switch = require("mdview.bindings.autocmds.buffer_switch")
local vim_leave = require("mdview.bindings.autocmds.vim_leave")
local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")
local breadcrumbs = require("mdview.bindings.autocmds.breadcrumbs")
-- local on_text_change = require("mdview.bindings.autocmds.on_text_change")
-- local bufwrite = require("mdview.bindings.autocmds.bufwrite")
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}
M.augroup_id = nil

--- Detach and remove augroup
function M.teardown()
	if not M.augroup_id then
		return
	end
	autocmd_registry.detach_all()
	pcall(require("mdview.adapter.inbound_poll").stop)
	pcall(api.nvim_del_augroup_by_id, M.augroup_id)
	M.augroup_id = nil
end

--- Attach all autocommands in a single augroup
function M.attach()
	if M.augroup_id then
		return
	end

	-- `group()`, not `get_augroup()`: the latter caches the augroup id by name
	-- and keeps handing back the SAME id after M.teardown() deleted it
	-- (nvim_del_augroup_by_id), so the next attach passed a stale id to
	-- nvim_create_autocmd ("Invalid 'group': N") and aborted the whole start.
	-- `group()` verifies its cache against Neovim and re-creates a group that
	-- was deleted behind it; clearing through it also drops the previous
	-- session's records, which the raw API cannot do -- so a restart used to
	-- leave dead rows in the generated bindings table.
	M.augroup_id = require("lib.nvim.bindings.autocmd").group("MdviewAutocmds", true)

	bufenter.attach(M.augroup_id) -- BufEnter snapshot
	buffer_switch.attach(M.augroup_id) -- Apply browser.behavior on buffer switch
	live_push.attach(M.augroup_id) -- Live Markdown push (diffs + full push on write)
	scroll_sync.attach(M.augroup_id) -- nvim-to-browser scroll sync (config: scroll_sync)
	breadcrumbs.attach(M.augroup_id) -- Session breadcrumbs (config: breadcrumbs)
	vim_leave.attach(M.augroup_id) -- Stop server on VimLeave

	-- Browser->Neovim inbound poller (click-to-navigate + reverse scroll; no-op
	-- unless one is enabled). Not an autocmd, but shares the session lifecycle —
	-- started here, stopped in teardown.
	pcall(require("mdview.adapter.inbound_poll").start)

	-- optional debug/legacy modules
	-- on_text_change.attach(M.augroup_id)
	-- bufwrite.attach(M.augroup_id)
end

return M

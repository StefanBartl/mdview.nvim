--- @module 'mdview.autocmds.bufenter'
--- Autocmd: BufEnter snapshot handling

---@diagnostic disable: undefined-global, unused-local

local api = vim.api
local session = require("mdview.core.session")
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")
local copy_lines = require("mdview.helper.copy_lines")
local normalize = require("mdview.helper.normalize")
local log = require("mdview.helper.log")
local defaults = require("mdview.config").defaults
local autocmds_registry =require("mdview.helper.autocmds_registry")

-- AUDIT: Neben vime_leave und bufenter auch andere autcmds id nach state?
local state = require("mdview.core.state")

local M = {}


-- on BufEnter, store snapshot if not present
---@param bufnr integer
---@return nil
local function on_buf_enter(bufnr)
	-- check filetype quickly
	local ft = safe_buf_get_option(bufnr, "filetype") or ""
	if ft ~= "markdown" and ft ~= "md" then
		return
	end

	local path = api.nvim_buf_get_name(bufnr)
	if path == "" then
		return
	end

	local norm_path = normalize.path(path)
	if not norm_path then
		log.debug("normalized path is nil", vim.log.levels.ERROR, "events", true)
		return
	end

	-- only store snapshot if we don't already have it
	if not session.get(norm_path) then
		local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
		session.store(norm_path, copy_lines(lines))
		log.debug("BufEnter snapshot stored for path: " .. norm_path, nil, "bufenter", true)
	end
end

--- Setup BufEnter autocmd in the given augroup.
--- @param group integer|nil  # nvim augroup id (optional). If nil, autocmd will be created without group.
function M.attach(group)
	local opts = {
		desc = "[mdview] Snapshot on enter",
		pattern = defaults.ft_pattern,
		callback = function(args)
			on_buf_enter(args.buf)
		end,
	}
	if group then
		opts.group = group
	end

	local id = api.nvim_create_autocmd("BufEnter", opts)
	if group then
		state._autocmd_ids[group] = state._autocmd_ids[group] or {}
		autocmds_registry.register(group, id)
	end
end

return M

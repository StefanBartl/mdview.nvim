---@module 'mdview.autocmds.on_text_changed'
-- Live markdown push on insert/change

local api = vim.api
local push_buffer = require("mdview.core.events").push_buffer
local log = require("mdview.helper.log")
local defaults = require("mdview.config").defaults
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

local function on_text_changed(bufnr)
	log.debug("TextChanged fired for buf " .. bufnr, nil, "textchange", true)
	push_buffer(bufnr, false) -- only push diffs
end

--- @param group integer|nil
function M.attach(group)
	local opts = {
		desc = "[mdview] Push on insert/change",
		pattern = defaults.ft_pattern,
		callback = function(args)
			on_text_changed(args.buf)
		end,
	}
	if group then
		opts.group = group
	end

	local id = api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, opts)
	if group then
		M._autocmd_ids[group] = M._autocmd_ids[group] or {}
		autocmd_registry.register(group, id)
	end
end

return M

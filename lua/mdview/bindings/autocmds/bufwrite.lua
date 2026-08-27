--- @module 'mdview.bindings.autocmds.bufwrite'
--- Autocmd: BufWritePost full-push handling

---@diagnostic disable: undefined-global, unused-local
local events = require("mdview.core.events")
local log = require("mdview.helper.log")
local autocmd = require("lib.nvim.bindings.autocmd")
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

--- Setup BufWritePost autocmd in the given augroup.
--- @param group integer|nil
function M.attach(group)
	---@internal
	---@param bufnr integer
	local function on_buf_write(bufnr)
		-- delegate to core.events push_buffer (force full push)
		pcall(function()
			events.push_buffer(bufnr, true)
		end)
		log.debug("BufWritePost fired and delegated to push_buffer for buf: " .. tostring(bufnr), nil, "bufwrite", true)
	end

	local opts = {
		desc = "[mdview] Push full buffer on write",
	}
	if group then
		opts.group = group
	end

	local id = autocmd.create({ "BufWritePost" }, function(args)
		on_buf_write(args.buf)
	end, opts)
	if group then
		autocmd_registry.register(group, id)
	end
end

return M

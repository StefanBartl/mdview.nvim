---@module 'mdview.bindings.autocmds.preview_tab_sync'
-- Keeps any open nvim-tab preview (mdview.adapter.preview_tab) in sync with
-- its source buffer's content. Entirely independent of :MDViewStart / the
-- relay session's MdviewAutocmds augroup — these autocmds are created once,
-- lazily, the first time a tab preview is opened (mdview.adapter.preview_tab
-- calls M.ensure_attached()), and stay registered globally for the rest of
-- the Neovim session. That's safe because the callback is gated on
-- preview_tab.is_open(bufnr), making it a cheap no-op whenever no preview is
-- open for the buffer being edited.

local api = vim.api

local M = {}
local attached = false

---@param bufnr integer
local function on_change(bufnr)
	local preview_tab = require("mdview.adapter.preview_tab")
	if preview_tab.is_open(bufnr) then
		preview_tab.sync(bufnr)
	end
end

--- Idempotent: only ever creates the autocmds once per Neovim session.
function M.ensure_attached()
	if attached then
		return
	end
	attached = true

	local group = api.nvim_create_augroup("MdviewPreviewTabSync", { clear = true })
	api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
		group = group,
		desc = "[mdview] Sync open nvim-tab preview(s) with their source buffer",
		callback = function(args)
			on_change(args.buf)
		end,
	})
end

return M

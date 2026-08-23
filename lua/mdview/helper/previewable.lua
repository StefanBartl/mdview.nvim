---@module 'mdview.helper.previewable'
--- Shared "is this buffer something mdview should preview" gate, used by every
--- autocmd that drives the preview (BufEnter snapshot, live push, breadcrumbs,
--- scroll sync, buffer switch). Centralized here because widening
--- `ft_pattern` to `{"*"}` (see mdview.config.merge, experimental.any_file)
--- makes Neovim's own glob matching fire for every named buffer — this is
--- what keeps terminal/help/quickfix/scratch buffers out; without it that
--- exclusion was previously just an accidental side effect of the
--- Markdown-only `ft_pattern` default.

local api = vim.api
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")

local M = {}

--- Whether `bufnr` is a buffer mdview should preview.
---@param bufnr integer
---@return boolean
function M.is(bufnr)
	local defaults = require("mdview.config").defaults

	local ok_bt, buftype = pcall(safe_buf_get_option, bufnr, "buftype")
	buftype = ok_bt and buftype or ""
	if buftype ~= "" then
		-- excludes terminal, help, quickfix, nofile/scratch, prompt, …
		return false
	end

	local ok_name, name = pcall(api.nvim_buf_get_name, bufnr)
	name = ok_name and name or ""
	if name == "" or name == defaults.log_buffer_name then
		return false
	end

	local ok_bin, binary = pcall(safe_buf_get_option, bufnr, "binary")
	if ok_bin and binary then
		return false
	end

	if defaults.experimental and defaults.experimental.any_file == true then
		return true
	end

	local ok_ft, ft = pcall(safe_buf_get_option, bufnr, "filetype")
	ft = ok_ft and ft or ""
	return ft == "markdown" or ft == "md"
end

return M

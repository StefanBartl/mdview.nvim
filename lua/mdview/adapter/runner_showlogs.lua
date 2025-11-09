
local api = vim.api
---@diagnostic disable-next-line
local buf_set_option = api.nvim_buf_set_option
local log = require("mdview.adapter.log")
local cfg = require("mdview.config")

local M = {}

log.setup({
  debug = true,            -- disable debug mode by default
  buf_name = "mdview_logs",      -- buffer name for display
  file_path = cfg.LOG_BUF_NAME,    -- timestamped logfile path
})

-- Open or reuse a named scratch buffer and populate it with log_lines (read-only)
---@return nil
local function open_log_buffer(log_lines)
	-- find existing buffer by name
	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(bufnr) and api.nvim_buf_get_name(bufnr) == cfg.LOG_BUF_NAME then
			-- populate and show
			buf_set_option(bufnr, "modifiable", true)
			api.nvim_buf_set_lines(bufnr, 0, -1, false, log_lines)
			buf_set_option(bufnr, "modifiable", false)
			api.nvim_set_current_buf(bufnr)
			return
		end
	end
	-- create new scratch buffer
	local bufnr = api.nvim_create_buf(false, true)
	api.nvim_buf_set_name(bufnr, cfg.LOG_BUF_NAME)
	buf_set_option(bufnr, "buftype", "nofile")
	buf_set_option(bufnr, "bufhidden", "wipe")
	buf_set_option(bufnr, "modifiable", true)
	api.nvim_buf_set_lines(bufnr, 0, -1, false, log_lines)
	buf_set_option(bufnr, "modifiable", false)
	api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = math.floor(vim.o.columns * 0.8),
		height = math.floor(vim.o.lines * 0.6),
		row = math.floor(vim.o.lines * 0.1),
		col = math.floor(vim.o.columns * 0.1),
		style = "minimal",
		border = "single",
	})
end

-- Public helper to open logs (callable from user, e.g., via :lua require('mdview.adapter.runner').show_logs())
---@return nil
function M.show_logs()
	vim.schedule(open_log_buffer)
end

return M

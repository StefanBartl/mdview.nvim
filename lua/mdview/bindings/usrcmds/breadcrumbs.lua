---@module 'mdview.bindings.usrcmds.breadcrumbs'
-- Actions behind :MDView breadcrumbs [export [path] | clear] — show/export/clear
-- the session breadcrumbs (mdview.core.breadcrumbs): a rough Markdown outline of
-- which document + heading section was visited when, useful for writing notes
-- and follow-ups after a call. Complements :MDView log (the internal log ring);
-- this is a human-facing session summary.

local notify = require("lib.nvim.notify").create("").notify

local M = {}

---@param lines string[]
local function show_in_scratch(lines)
	vim.cmd("botright new")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].modifiable = false
	pcall(vim.api.nvim_buf_set_name, buf, "mdview://breadcrumbs")
end

--- Show the breadcrumbs outline in a scratch buffer.
---@return nil
function M.show()
	show_in_scratch(require("mdview.core.breadcrumbs").format())
end

--- Write the breadcrumbs outline to `path` (default: stdpath log).
---@param path string|nil
---@return nil
function M.export(path)
	local crumbs = require("mdview.core.breadcrumbs")
	if not path or path == "" then
		local dir = vim.fn.stdpath("log")
		pcall(vim.fn.mkdir, dir, "p")
		path = dir .. "/mdview-breadcrumbs.md"
	end
	local f = io.open(path, "w")
	if f then
		f:write(table.concat(crumbs.format(), "\n") .. "\n")
		f:close()
		notify("[mdview] breadcrumbs written to " .. path, vim.log.levels.INFO)
	else
		notify("[mdview] failed to write breadcrumbs to " .. path, vim.log.levels.ERROR)
	end
end

--- Drop all recorded breadcrumbs.
---@return nil
function M.clear()
	require("mdview.core.breadcrumbs").clear()
	notify("[mdview] breadcrumbs cleared", vim.log.levels.INFO)
end

return M

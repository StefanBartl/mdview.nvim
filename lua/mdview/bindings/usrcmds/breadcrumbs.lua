---@module 'mdview.bindings.usrcmds.breadcrumbs'
-- Registers :MDViewBreadcrumbs [show|export [path]|clear] — show/export/clear the
-- session breadcrumbs (mdview.core.breadcrumbs): a rough Markdown outline of
-- which document + heading section was visited when, useful for writing notes
-- and follow-ups after a call. Complements :MDViewLog (which shows the internal
-- log ring); this is a human-facing session summary.

local libusercmd = require("lib.nvim.usercmd")

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

function M.attach()
	libusercmd.create("MDViewBreadcrumbs", function(cmdopts)
		local crumbs = require("mdview.core.breadcrumbs")
		local args = cmdopts.fargs or {}
		local sub = (args[1] or "show"):lower()

		if sub == "clear" then
			crumbs.clear()
			vim.notify("[mdview] breadcrumbs cleared", vim.log.levels.INFO)
			return
		end

		if sub == "export" then
			local path = args[2]
			if not path or path == "" then
				local dir = vim.fn.stdpath("log")
				pcall(vim.fn.mkdir, dir, "p")
				path = dir .. "/mdview-breadcrumbs.md"
			end
			local f = io.open(path, "w")
			if f then
				f:write(table.concat(crumbs.format(), "\n") .. "\n")
				f:close()
				vim.notify("[mdview] breadcrumbs written to " .. path, vim.log.levels.INFO)
			else
				vim.notify("[mdview] failed to write breadcrumbs to " .. path, vim.log.levels.ERROR)
			end
			return
		end

		if sub ~= "show" then
			vim.notify("[mdview] MDViewBreadcrumbs: expected show | export [path] | clear", vim.log.levels.WARN)
			return
		end

		show_in_scratch(crumbs.format())
	end, {
		desc = "[mdview] Show/export/clear session breadcrumbs (document + heading over time)",
		nargs = "*",
		complete = function(arglead)
			local out = {}
			for _, c in ipairs({ "show", "export", "clear" }) do
				if c:find(arglead, 1, true) == 1 then
					out[#out + 1] = c
				end
			end
			return out
		end,
	})
end

return M

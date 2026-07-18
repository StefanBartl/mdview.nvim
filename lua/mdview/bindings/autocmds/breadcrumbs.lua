---@module 'mdview.bindings.autocmds.breadcrumbs'
-- Records session breadcrumbs (mdview.core.breadcrumbs) as the cursor moves and
-- on buffer switches, so :MDViewBreadcrumbs can show/export a rough outline of
-- what was visited during the session. Gated behind config.breadcrumbs (default
-- true); throttled, and the recorder itself dedupes on (doc, heading), so this
-- stays off the hot path.

local api = vim.api
local defaults = require("mdview.config").defaults
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

local last_at = 0

---@param group integer|nil
function M.attach(group)
	if defaults.breadcrumbs == false then
		return
	end

	local crumbs = require("mdview.core.breadcrumbs")
	crumbs.clear() -- fresh session

	local opts = {
		desc = "[mdview] Record session breadcrumbs (document + heading over time)",
		pattern = defaults.ft_pattern,
		callback = function(args)
			local now = (vim.uv or vim.loop).now()
			if now - last_at < 300 then
				return
			end
			last_at = now
			pcall(crumbs.record, args.buf)
		end,
	}
	if group then
		opts.group = group
	end
	local id = api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, opts)
	autocmd_registry.register(group, id)

	-- Seed the first breadcrumb for the current buffer (no BufEnter fires when a
	-- session starts on the already-current buffer).
	pcall(crumbs.record, api.nvim_get_current_buf())
end

return M

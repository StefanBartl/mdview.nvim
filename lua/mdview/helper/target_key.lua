---@module 'mdview.helper.target_key'
--- Resolve the room key a piece of outgoing traffic (content push, scroll
--- ping, live-control update) should target.
---
--- In `browser.behavior = "reuse"` the single open preview tab follows the
--- active buffer, so everything should route to the room the tab actually
--- watches (`state.preview_key`) rather than the buffer's own path — falling
--- back to the buffer's own path only when no tab has been opened yet (state
--- has no preview_key). In any other behavior ("new_tab"/"manual"), each
--- buffer gets its own room, so the buffer's own path is always the target.
---
--- Every outgoing channel needs this SAME rule (content push, scroll/cursor
--- sync, live-control) — previously duplicated ad hoc per module, which let
--- scroll_sync.lua drift out of sync and silently target the wrong room after
--- a buffer switch in "reuse" mode (see DONE.md BUGS).

local normalize = require("mdview.helper.normalize")

local M = {}

--- @param bufnr integer|nil # defaults to the current buffer (0)
--- @return string|nil key
function M.resolve(bufnr)
	local behavior = require("mdview.config.browser").defaults.behavior or "reuse"
	if behavior == "reuse" then
		local pk = require("mdview.core.state").get_preview_key()
		if type(pk) == "string" and pk ~= "" then
			return pk
		end
	end

	local path = vim.api.nvim_buf_get_name(bufnr or 0)
	if not path or path == "" then
		return nil
	end
	return normalize.path(path) or path
end

return M

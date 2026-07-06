---@module 'mdview.core.session'
-- Session management and simple buffer-content tracking for mdview.nvim.
-- Stores last-seen buffer contents (by absolute path) to enable minimal diffing later.

local normalize = require("mdview.helper.normalize")
local log = require("mdview.helper.log")

local M = {}

M.buffers = {}

-- Initialize session store.
---@return nil
function M.init()
	M.buffers = {}
end

-- Shutdown session and clear cached contents.
---@return nil
function M.shutdown()
	M.buffers = {}
end

-- Get cached object for path.
---@param path string
---@return table|nil
function M.get(path)
	return M.buffers[path]
end

-- Store buffer content snapshot (lines array) and computed hash
---@param path string
---@param lines string[]
function M.store(path, lines)
	local norm_path = normalize.path(path)
	if norm_path then
		path = norm_path
	else
		log.debug("normalized path ist nil", vim.log.levels.ERROR, "", true)
		return
	end

	-- sha256 is fine regardless of file size (not a bottleneck for markdown
	-- files); table.concat's one-time allocation to build `text` is the only
	-- cost here and is negligible at realistic markdown file sizes.
	local text = table.concat(lines, "\n")
	local h = vim.fn.sha256(text)
	M.buffers[path] = { hash = h, lines = lines }
end

-- Naive line-diff (finds first/last differing line only, no LCS). Dormant —
-- not on the current live-push path (see core/events.lua's module docstring
-- and docs/Roadmap/Roadmap.md); utils/diff_granular.lua has a proper Myers
-- LCS-based diff ready to swap in if this transport is reactivated.
--
-- Compute a lightweight diff between cached lines and new lines.
-- Returns a table of change ranges: { { start = n, ["end"] = m, lines = {...} }, ... }
---@param old_lines string[]|nil
---@param new_lines string[]
---@return table change_ranges
function M.compute_line_diff(old_lines, new_lines)
	if not old_lines then
		return { { start = 1, ["end"] = #new_lines, lines = new_lines } }
	end

	local i = 1
	local j = #old_lines
	local k = #new_lines

	-- find first differing line
	while i <= j and i <= k and old_lines[i] == new_lines[i] do
		i = i + 1
	end

	-- if no change
	if i > j and i > k then
		return {}
	end

	-- find last differing line (from end)
	local ei = j
	local ek = k
	while ei >= i and ek >= i and old_lines[ei] == new_lines[ek] do
		ei = ei - 1
		ek = ek - 1
	end

	-- construct range in new_lines
	local changed = {}
	local start_idx = i
	local end_idx = ek
	if start_idx <= end_idx then
		local slice = {}
		for idx = start_idx, end_idx do
			table.insert(slice, new_lines[idx])
		end
		table.insert(changed, { start = start_idx, ["end"] = end_idx, lines = slice })
	end

	return changed
end

return M

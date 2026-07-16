---@module 'mdview.utils.line_diff'
-- Minimal, correct line diff for the opt-in line-diff transport
-- (experimental.line_diff). Computes the single contiguous changed region
-- between two line arrays by matching the common prefix and suffix, and
-- returns one 0-based edit that splice(start, count, ...lines) reproduces
-- exactly on the client (see src/client/render/diffDoc.ts).
--
-- For live typing this is both correct and near-optimal: edits almost always
-- touch one contiguous region. Multiple simultaneous edits (e.g. multi-cursor)
-- collapse into one larger replace spanning them — still correct, just less
-- minimal than a full LCS diff. Preferred over the older utils/diff_granular
-- (a buggy Myers attempt that dropped real changes); kept simple on purpose.
--
-- Delegates the common-prefix/common-suffix computation to lib.lua.diff.lines
-- (same algorithm), adapted from its 1-based {start, a_end, b_end} region
-- shape to this module's 0-based client-splice shape.
---@param old string[]|nil previous lines
---@param new string[]|nil current lines
---@return { start: integer, count: integer, lines: string[] }|nil  # nil when unchanged
return function(old, new)
	old = old or {}
	new = new or {}

	local region = require("lib.lua.diff.lines").diff(old, new)
	if not region then
		return nil
	end

	local lines = {}
	for k = region.start, region.b_end do
		lines[#lines + 1] = new[k]
	end

	return {
		start = region.start - 1, -- 0-based for the client's Array.splice
		count = math.max(0, region.a_end - region.start + 1), -- old lines removed
		lines = lines, -- replacement lines
	}
end

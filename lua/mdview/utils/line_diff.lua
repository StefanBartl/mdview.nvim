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
---@param old string[]|nil previous lines
---@param new string[]|nil current lines
---@return { start: integer, count: integer, lines: string[] }|nil  # nil when unchanged
return function(old, new)
	old = old or {}
	new = new or {}

	-- common prefix length
	local i = 1
	while i <= #old and i <= #new and old[i] == new[i] do
		i = i + 1
	end

	-- common suffix (not overlapping the matched prefix)
	local jo, jn = #old, #new
	while jo >= i and jn >= i and old[jo] == new[jn] do
		jo = jo - 1
		jn = jn - 1
	end

	-- nothing changed
	if i > jo and i > jn then
		return nil
	end

	local lines = {}
	for k = i, jn do
		lines[#lines + 1] = new[k]
	end

	return {
		start = i - 1, -- 0-based for the client's Array.splice
		count = math.max(0, jo - i + 1), -- old lines removed
		lines = lines, -- replacement lines
	}
end

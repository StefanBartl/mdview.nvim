---@module 'mdview.helper.path_join'
-- Small path join helper (forward slashes are fine on Windows with luv)

---@param ... string  # one or more path segments to join
---@return string # concatenated path using forward slashes
return function (...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = select(i, ...)
	end
	return table.concat(parts, "/")
end

---@module 'mdview.helper.is_windows'
-- Detect Windows OS in a robust way (uv.os_uname may be nil in some environments)

---@diagnostic disable: undefined-field

local uv = vim.loop

---@return string|boolean
return function ()
	local ok, uname = pcall(uv.os_uname)
	if not ok or not uname or not uname.version then
		return false
	end
	return tostring(uname.version):match("Windows") and true or false
end


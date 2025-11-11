---@module 'mdview.helper.file_exists'
-- Check file existence using luv

---@diagnostic disable: undefined-field

local uv = vim.loop
local normalize = require("mdview.helper.normalize")

---@param path string  # file or directory path to check
---@return boolean  # true if the path exists, false otherwise
return function (path)
	local normalized = normalize.path(path)
	return uv.fs_stat(normalized) ~= nil
end

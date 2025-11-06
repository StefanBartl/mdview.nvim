---@module 'mdview.helper.normalize'
--- Helper utilities to normalize file paths for internal comparison and for use in URLs.
--- Provides:
---  - normalize_path(path): convert backslashes to forward-slashes (Windows -> POSIX style)
---  - normalize_path_for_url(path): normalize then escape using fnameescape for safe use as a query key

--[[ USAGE:
local normalize = require("mdview.helper.normalize")
local log = require("mdview.helper.log")

local norm_path = normalize.path(path)
if norm_path then
	path = norm_path
else
	log.debug("normalized path ist nil", vim.log.levels.ERROR, "", true)
	return
end

]]--

local M = {}

---@param path string
---@return string|nil
function M.path(path)
  if not path then
    return nil
  end
	---@diagnostic disable-next-line
  return tostring(path):gsub("\\", "/")
end

---@param path string
---@return string|nil
function M.path_for_url(path)
  if not path then
    return nil
  end
  local s = tostring(path):gsub("\\", "/")
  return vim.fn.fnameescape(s)
end

return M

---@module 'mdview.helper.normalize'
--- Helper utilities to normalize file paths for internal comparison and for use in URLs.
--- Provides:
---  - normalize_path(path): convert backslashes to forward-slashes (Windows -> POSIX style),
---    delegating to lib.nvim's cross-platform separator helper
---  - normalize_path_for_url(path): normalize then percent-encode for safe use as a URL query value

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

local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")

local M = {}

---@param path string
---@return string|nil
function M.path(path)
  if not path then
    return nil
  end
  return unify_slashes(tostring(path))
end

---@param path string
---@return string|nil
function M.path_for_url(path)
  if not path then
    return nil
  end
  return vim.uri_encode(unify_slashes(tostring(path)))
end

return M

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

]]
--

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
	-- rfc2396, NOT the default: the default mode leaves ":" and "/" unencoded,
	-- so a Windows path stays "C:/Users/...". Windows' rundll32
	-- FileProtocolHandler (how :MDView start opens the default browser) then
	-- treats the embedded "C:" as a drive/file reference and never opens the
	-- URL — the exact reason the browser tab silently failed to appear while
	-- :MDView standalone (whose Go side url.QueryEscape's the key) worked. Both
	-- forms decode back to the same path server-side, so the relay room key is
	-- unchanged; this only removes the bare "C:" from the emitted URL.
	return vim.uri_encode(unify_slashes(tostring(path)), "rfc2396")
end

return M

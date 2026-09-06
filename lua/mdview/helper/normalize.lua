---@module 'mdview.helper.normalize'
--- Normalize file paths for internal comparison and for use in URLs.
---  - M.path(path): convert backslashes to forward slashes (Windows -> POSIX
---    style), delegating to lib.nvim's cross-platform separator helper
---  - M.path_for_url(path): normalize, then percent-encode for safe use as a
---    URL query value

local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")

local M = {}

---@param path string|nil A missing path is answered with nil, not raised on.
---@return string|nil
function M.path(path)
  if not path then
    return nil
  end
  return unify_slashes(tostring(path))
end

---@param path string|nil A missing path is answered with nil, not raised on.
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

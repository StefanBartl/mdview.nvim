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
---@return mdview.session.entry|nil
function M.get(path)
  return M.buffers[path]
end

-- An entry's `hash` is computed on first read and memoized, not at store time.
-- store() runs on every throttled live push (about every 150 ms while typing)
-- and nothing in the plugin reads the hash, so hashing eagerly cost a
-- table.concat plus a sha256 over the whole document per push (about 20 ms at
-- 100k lines) for a value nobody asked for. `lines` is kept by reference, so a
-- hash read later covers the lines as they are at that moment.
---@type metatable
local entry_mt = {
  __index = function(entry, key)
    if key ~= "hash" then
      return nil
    end
    local h = vim.fn.sha256(table.concat(rawget(entry, "lines") or {}, "\n"))
    rawset(entry, "hash", h)
    return h
  end,
}

-- Store a buffer content snapshot (lines array) under its normalized path. The
-- hash of the snapshot is available as `entry.hash`, computed lazily (see above).
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

  M.buffers[path] = setmetatable({ lines = lines }, entry_mt)
end

-- Naive line-diff (finds first/last differing line only, no LCS). Dormant —
-- not on the current live-push path (see core/events.lua module docstring);
-- utils/diff_granular.lua has a proper Myers
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

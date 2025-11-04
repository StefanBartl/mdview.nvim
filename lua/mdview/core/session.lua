---@module 'mdview.core.session'
--- Session management and simple buffer-content tracking for mdview.nvim.
--- Stores last-seen buffer contents (by absolute path) to enable minimal diffing later.

local crypto = vim.loop -- using uv for portability where needed (no heavy deps)

local M = {}
M.buffers = {}

local function path_of(bufnr)
  return vim.api.nvim_buf_get_name(bufnr)
end

--- Initialize session store.
function M.init()
  M.buffers = {}
end

--- Shutdown session and clear cached contents.
function M.shutdown()
  M.buffers = {}
end

--- Get cached object for path.
---@param path string
---@return table|nil
function M.get(path)
  return M.buffers[path]
end

--- Store buffer content snapshot (lines array) and computed hash.
---@param path string
---@param lines string[]
function M.store(path, lines)
  -- simple stable hash using table concat; for large files replace with better hash
  local text = table.concat(lines, "\n")
  local h = vim.fn.sha256(text)
  M.buffers[path] = { hash = h, lines = lines }
end

--- Compute a lightweight diff between cached lines and new lines.
--- Returns a table of change ranges: { { start = n, ["end"] = m, lines = {...} }, ... }
--- This is a naive line-diff: it finds first/last differing line. Suitable as a first step.
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

---@module 'mdview.utils.diff_granular'
-- Line-based minimal diff using Myers LCS algorithm.
-- 1-based indexing, nil-safe, produces edits suitable for incremental sending.

-- AUDIT: Optimize it

---@param old_lines string[]|nil previous lines
---@param new_lines string[] current lines
---@return table[] list of edits { op="replace"|"insert"|"delete", start=number, count=number, lines=string[]? }
return function(old_lines, new_lines)
  old_lines = old_lines or {}
  new_lines = new_lines or {}

  local N = #old_lines
  local M = #new_lines
  local max_d = N + M
  local v = {}
  v[1] = 0
  local trace = {}

  -- Myers diff main loop
  for d = 0, max_d do
    local v_snapshot = {}
    for k = -d, d, 2 do
      local x
      if k == -d or (k ~= d and (v[k - 1] or 0) < (v[k + 1] or 0)) then
        x = v[k + 1] or 0
      else
        x = (v[k - 1] or 0) + 1
      end
      local y = x - k
      -- extend along equal lines
      while x < N and y < M and (old_lines[x + 1] or "") == (new_lines[y + 1] or "") do
        x = x + 1
        y = y + 1
      end
      v_snapshot[k] = x
      if x >= N and y >= M then
        table.insert(trace, v_snapshot)
        goto done
      end
    end
    table.insert(trace, v_snapshot)
    v = v_snapshot
  end
  ::done::

  -- Backtrace edits
  local edits = {}
  local x, y = N, M
  for d = #trace, 1, -1 do
    local v_map = trace[d]
    local k = x - y
    local prev_k
    if k == -d or (k ~= d and (v_map[k - 1] or 0) < (v_map[k + 1] or 0)) then
      prev_k = k + 1
    else
      prev_k = k - 1
    end
    local prev_x = v_map[prev_k] or 0
    local prev_y = prev_x - prev_k

    local dx = x - prev_x
    local dy = y - prev_y

    if dx == 1 and dy == 1 then
      -- matched line, no edit
    elseif dx == 1 then
      table.insert(edits, { op = "delete", start = prev_x, count = 1 })
    elseif dy == 1 then
      table.insert(edits, { op = "insert", start = prev_x, count = 1, lines = { new_lines[prev_y + 1] or "" } })
    end

    x, y = prev_x, prev_y
  end

  -- reverse for start->end order
  local ordered = {}
  for i = #edits, 1, -1 do table.insert(ordered, edits[i]) end
  return ordered
end

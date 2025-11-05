---@module 'mdview.test.apply'
-- Apply patch objects created by compute_line_diff (prefix/suffix heuristic).

local M = {}

---@param old_lines string[] previous lines
---@param diffs table[] list of edits returned by compute_line_diff
---@return string[] patched_lines
function M.apply_patch(old_lines, diffs)
  -- If no diffs, return copy of old_lines
  if not diffs or #diffs == 0 then
    local copy = {}
    for i=1, #old_lines do copy[i] = old_lines[i] end
    return copy
  end

  -- start from old_lines copy
  local out = {}
  for i=1, #old_lines do out[i] = old_lines[i] end

  -- For the simple prefix/suffix diff we expect single replace op
  for _, d in ipairs(diffs) do
    if d.op == "replace" then
      local before = vim.list_slice(out, 1, d.start)
      local after = vim.list_slice(out, d.start + (d.count or 0) + 1, #out)
      local merged = {}
      for i=1, #before do table.insert(merged, before[i]) end
      for i=1, #d.lines do table.insert(merged, d.lines[i]) end
      for i=1, #after do table.insert(merged, after[i]) end
      out = merged
    elseif d.op == "insert" then
      local before = vim.list_slice(out, 1, d.start)
      local after = vim.list_slice(out, d.start + 1, #out)
      local merged = {}
      for i=1, #before do table.insert(merged, before[i]) end
      for i=1, #d.lines do table.insert(merged, d.lines[i]) end
      for i=1, #after do table.insert(merged, after[i]) end
      out = merged
    elseif d.op == "delete" then
      local before = vim.list_slice(out, 1, d.start)
      local after = vim.list_slice(out, d.start + (d.count or 0) + 1, #out)
      local merged = {}
      for i=1, #before do table.insert(merged, before[i]) end
      for i=1, #after do table.insert(merged, after[i]) end
      out = merged
    else
      error("unsupported op: "..tostring(d.op))
    end
  end

  return out
end

return M

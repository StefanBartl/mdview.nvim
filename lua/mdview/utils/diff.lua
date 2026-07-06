---@module 'mdview.utils.diff'
-- Very small line-diff: compute contiguous changed ranges. Only used by
-- test/diff_harness.lua — dormant along with the rest of the line-diff
-- transport this was built for (see core/events.lua's module docstring and
-- docs/Roadmap/Roadmap.md). If reactivated, replacing this prefix/suffix
-- scan with a proper LCS-based (Myers) diff is worth revisiting for correctness
-- on interleaved edits — it currently only handles a single contiguous change.
---@param old_lines string[]|nil
---@param new_lines string[]
---@return DiffEdit[] list of diffs
return function(old_lines, new_lines)
  -- Treat nil or empty old_lines as full replace
  if not old_lines then
    return { { op = "replace", start = 0, count = 0, lines = new_lines } }
  elseif #old_lines == 0 then
    return { { op = "replace", start = 0, count = 0, lines = new_lines } }
  end

  -- Find prefix equality
  local i = 1
  while i <= #old_lines and i <= #new_lines and old_lines[i] == new_lines[i] do
    i = i + 1
  end

  -- Find suffix equality
  local j_old = #old_lines
  local j_new = #new_lines
  while j_old >= i and j_new >= i and old_lines[j_old] == new_lines[j_new] do
    j_old = j_old - 1
    j_new = j_new - 1
  end

  -- [i..j_old] replaced by [i..j_new]
  local diffs = {}
  if i <= j_old or i <= j_new then
    table.insert(diffs, {
      op = "replace",
      start = i - 1,
      count = math.max(0, j_old - i + 1),
      lines = vim.list_slice(new_lines, i, j_new),
    })
  end

  return diffs
end


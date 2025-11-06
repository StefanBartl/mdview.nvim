---@module 'mdview.helper.copy_lines'

-- Deep copy function to prevent old_lines being overwritten
---@param lines table
---@return table
return function (lines)
  local t = {}
  for i = 1, #lines do t[i] = lines[i] end
  return t
end

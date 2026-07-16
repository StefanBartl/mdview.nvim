---@module 'mdview.helper.copy_lines'
---@description
--- Shallow array copy, delegating to lib.nvim's lib.lua.tables.clone
--- (mdview.nvim already hard-depends on lib.nvim) with a local fallback.

local ok_lib, lib_tables = pcall(require, "lib.lua.tables")
local has_lib_clone = ok_lib and type(lib_tables.clone) == "function"

---@param lines table
---@return table
return function(lines)
  if has_lib_clone then
    return lib_tables.clone(lines)
  end
  local t = {}
  for i = 1, #lines do t[i] = lines[i] end
  return t
end

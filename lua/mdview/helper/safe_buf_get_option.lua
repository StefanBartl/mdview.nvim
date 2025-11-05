---@module 'mdview.helper.safe_buf_get_option'
--- Backwards-compatible helper to read buffer-local options.
--- Tries multiple API variants (nvim_buf_get_option, nvim_buf_get_option_value,
--- vim.bo via nvim_buf_call) to support a wide range of Neovim versions.

---@diagnostic disable: undefined-field, deprecated, unused-local
local api = vim.api

--- Get buffer option in a backwards-compatible way.
--- Implementation notes:
--- 1. Try vim.api.nvim_buf_get_option(bufnr, name)
--- 2. Try vim.api.nvim_buf_get_option_value(name, { buf = bufnr })
--- 3. If the buffer is the current buffer, read vim.bo[name]
--- 4. As a last resort use vim.api.nvim_buf_call(bufnr, function() return vim.bo[name] end)
--- Each step is wrapped in pcall to avoid raising errors on older Neovim builds.
---@param bufnr integer buffer number
---@param name string option name
---@return any|nil option value or nil if not available
return function(bufnr, name)
  if not bufnr or not name then
    return nil
  end

  -- 1) try nvim_buf_get_option(bufnr, name)
  local ok, val = pcall(api.nvim_buf_get_option, bufnr, name)
  if ok then
    return val
  end

  -- 2) try nvim_buf_get_option_value(name, { buf = bufnr })
  ok, val = pcall(api.nvim_buf_get_option_value, name, { buf = bufnr })
  if ok then
    return val
  end

  -- 3) if requested buffer is the current one, try vim.bo
  local ok_cur, cur = pcall(api.nvim_get_current_buf)
  if ok_cur and cur == bufnr then
    local ok_bo, v = pcall(function() return vim.bo[name] end)
    if ok_bo then
      return v
    end
  end

  -- 4) fallback: use nvim_buf_call to safely read vim.bo for that buffer
  ok, val = pcall(api.nvim_buf_call, bufnr, function() return vim.bo[name] end)
  if ok then
    return val
  end

  return nil
end


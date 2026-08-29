---@module 'mdview.bindings.autocmds.on_text_changed'
-- Live markdown push on insert/change.
-- Dormant — not attached (see bindings/autocmds/init.lua); superseded by
-- bindings/autocmds/live_push.lua. Kept for reference.

local push_buffer = require("mdview.core.events").push_buffer
local log = require("mdview.helper.log")
local defaults = require("mdview.config").defaults
local autocmd = require("lib.nvim.bindings.autocmd")
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

---@internal
---@param bufnr integer
---@return nil
local function on_text_changed(bufnr)
  log.debug("TextChanged fired for buf " .. bufnr, nil, "textchange", true)
  push_buffer(bufnr, false) -- only push diffs
end

--- @param group integer|nil
function M.attach(group)
  local opts = {
    desc = "[mdview] Push on insert/change",
    pattern = defaults.ft_pattern,
  }
  if group then
    opts.group = group
  end

  local id = autocmd.create({ "TextChanged", "TextChangedI" }, function(args)
    on_text_changed(args.buf)
  end, opts)
  if group then
    autocmd_registry.register(group, id)
  end
end

return M

---@module 'mdview.helper.log'
-- Central debug logging helper for mdview.nvim.
-- Gates on mdview.config.defaults.debug_preview; delegates the actual
-- notification to lib.nvim's prefixed notifier.

local cfg = require("mdview.config")
local notify = require("lib.nvim.notify").create("[mdview]")

local M = {}

---@param msg string
---@param level integer? # vim.log.levels, default = INFO
---@param tag string? # optional sub-tag to customize the notification prefix
---@param debug boolean? # whether to actually log based on config
function M.debug(msg, level, tag, debug)
    level = level or vim.log.levels.INFO
    tag = tag or ""

    if debug and cfg.defaults.debug_preview then
        notify.notify(("[%s] %s"):format(tag, msg), level)
    end
end

return M

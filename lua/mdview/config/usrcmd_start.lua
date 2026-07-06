---@module 'mdview.config.usrcmd_start'
--- Configuration for the :MDViewStart command's initial-push strategy.

local M = {}

-- Shared with the top-level config: this is the same table object as
-- mdview.config's M.defaults.start (see config/DEFAULTS.lua), so overrides
-- passed to require('mdview').setup({ start = {...} }) are visible here too.
---@type mdview.config.StartDefaults
M.defaults = require("mdview.config").defaults.start

return M

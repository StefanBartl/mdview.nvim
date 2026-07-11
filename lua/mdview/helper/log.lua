---@module 'mdview.helper.log'
-- Thin debug-notification front-end over the shared mdview logger
-- (mdview.log, built on lib.nvim.logger).
--
-- Every call is RECORDED into the logger's in-memory ring (so
-- :MDViewDiagnose always has recent history); a vim.notify only happens when
-- the caller opts in AND mdview.config.defaults.debug_preview is on. Keeping
-- the (msg, level, tag, debug) signature means existing call sites are
-- unchanged.

local cfg = require("mdview.config")
local mlog = require("mdview.log")

local M = {}

---@param msg string
---@param level integer? # vim.log.levels, default = INFO
---@param tag string? # optional sub-tag recorded as context / notify prefix
---@param debug boolean? # when true (and debug_preview on), also vim.notify
function M.debug(msg, level, tag, debug)
	level = level or vim.log.levels.INFO
	tag = tag or ""

	local want_notify = (debug == true) and (cfg.defaults.debug_preview == true)
	mlog.instance.log(level, ("[%s] %s"):format(tag, msg), { tag = tag }, { notify = want_notify })
end

return M

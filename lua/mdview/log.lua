---@module 'mdview.log'
-- Central structured logger for mdview.nvim, built on lib.nvim.logger.
--
-- Every internal log call is recorded into a bounded in-memory ring
-- REGARDLESS of the user's debug config, so :MDViewDiagnose can dump a
-- recent history even when debug notifications are off. The debug config
-- (mdview.config.defaults.debug_preview) only controls what ADDITIONALLY
-- reaches vim.notify — see mdview.helper.log, which drives notifications
-- explicitly per call.

local logger = require("lib.nvim.logger")

local M = {}

--- The one shared logger instance for the whole plugin.
--- level = trace  -> capture everything into the ring
--- notify_level = OFF -> never auto-notify; callers pass { notify = true }
--- file = false   -> no persistent JSONL by default (the ring is dumped into
---                   the :MDViewDiagnose report instead)
M.instance = logger.new({
	name = "mdview",
	level = "trace",
	notify_level = vim.log.levels.OFF,
	file = false,
	history = 500,
})

--- Snapshot of the in-memory ring (array of records), most recent last.
---@return table[]
function M.snapshot()
	return M.instance.snapshot()
end

return M

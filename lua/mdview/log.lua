---@module 'mdview.log'
-- Central structured logger for mdview.nvim, built on lib.nvim.logger.
--
-- Every internal log call is recorded into a bounded in-memory ring
-- REGARDLESS of the user's debug config, so :MDViewDiagnose can dump a
-- recent history even when debug notifications are off. The debug config
-- (mdview.config.defaults.debug_preview) only controls what ADDITIONALLY
-- reaches vim.notify — see mdview.helper.log, which drives notifications
-- explicitly per call.

-- Defensive shim for a lib.nvim bug: lib/nvim/logger/init.lua and
-- lib/nvim/notify/resolve_log_level/init.lua run dangling
-- `require("@types.log")` / `require("lib.nvim.logger.@types")` calls (leftover
-- type-annotation artifacts). `@types.log` has no matching file, so the require
-- succeeds only on case-insensitive/loose filesystems (Windows) and FAILS on
-- Linux with "module '@types.log' not found", which would break mdview's whole
-- logger init there. Pre-populate package.loaded so those requires are no-ops
-- regardless of platform. Harmless once lib.nvim drops the bogus requires; the
-- proper fix is in lib.nvim itself.
package.loaded["@types.log"] = package.loaded["@types.log"] or true
package.loaded["lib.nvim.logger.@types"] = package.loaded["lib.nvim.logger.@types"] or true

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

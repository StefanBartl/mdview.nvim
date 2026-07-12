---@module 'mdview.bindings.usrcmds'
--- Registers mdview user commands: start, stop, open, show logs.
---
--- All user commands are registered once at setup() and never torn down —
--- they are the plugin's permanent command surface (like every other Neovim
--- plugin's :Commands), not something to attach/detach per preview session.
--- Only autocommands (mdview.bindings.autocmds) have a real attach/detach
--- lifecycle, since those genuinely need to stop firing once a session ends.

local open = require("mdview.bindings.usrcmds.open")
local start = require("mdview.bindings.usrcmds.start")
local stop = require("mdview.bindings.usrcmds.stop")
local show_weblogs = require("mdview.bindings.usrcmds.show_weblogs")
local preview_tab = require("mdview.bindings.usrcmds.preview_tab")
local diagnose = require("mdview.bindings.usrcmds.diagnose")
local toggle = require("mdview.bindings.usrcmds.toggle")
local theme = require("mdview.bindings.usrcmds.theme")
local log = require("mdview.bindings.usrcmds.log")

local M = {}

---@return nil
function M.attach()
	start.attach()
	stop.attach()
	open.attach()
	show_weblogs.attach()
	preview_tab.attach()
	diagnose.attach()
	toggle.attach()
	theme.attach()
	log.attach()
end

return M

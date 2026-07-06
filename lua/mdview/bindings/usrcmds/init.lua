---@module 'mdview.bindings.usrcmds'
--- Registers mdview user commands: start, stop, open, show logs

local open = require("mdview.bindings.usrcmds.open")
local start = require("mdview.bindings.usrcmds.start")
local stop = require("mdview.bindings.usrcmds.stop")
local show_weblogs = require("mdview.bindings.usrcmds.show_weblogs")
local usercmds_registry = require("mdview.helper.usercmds_registry")

local M = {}

---@return nil
function M.detach()
	usercmds_registry.detach_all() -- all non persistent
end

---@return nil
function M.attach()
	M.attach_persistent()
	M.attach_non_persistent()
end

-- They are available after detach(); they must be available outside of the runtime of the plugin to
---@return nil
function M.attach_persistent()
	start.attach()
	show_weblogs.attach()
end

---@return nil
function M.attach_non_persistent()
	open.attach()
	stop.attach()
end

return M

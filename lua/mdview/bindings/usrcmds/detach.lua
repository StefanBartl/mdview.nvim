---@module 'mdview.bindings.usrcmds.detach'
--- Action behind :MDView detach — start the preview in a *separate*, detached
--- Neovim process instead of this one.
---
--- Why a second Neovim rather than just :MDView start: the preview then no
--- longer dies with this instance, and it runs against scripts/minimal_init.lua
--- (only mdview.nvim + lib.nvim loaded), so it is isolated from whatever else
--- the user's config does. The typical use is "leave this doc previewing while
--- I close the editor / work in another instance".
---
--- The detached instance still runs the *normal* start path — same relay, same
--- autocmds, same browser handling — so the preview it produces is identical to
--- a foreground one. Only the process boundary differs. For a preview with no
--- Neovim in the chain at all, see :MDView standalone (usrcmds/standalone.lua).

local detached = require("mdview.adapter.detached")
local log = require("mdview.helper.log")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

--- Start a detached, minimal-config Neovim previewing `file` (default: the
--- current buffer's file).
---   :MDView detach
---   :MDView detach notes.md
---   :MDView detach notes.md --no-browser
---@param file_arg string|nil # path from the route's `file` arg
---@param no_browser boolean|nil # true when --no-browser was passed
function M.run(file_arg, no_browser)
	local target, err = detached.resolve_target(file_arg)
	if not target then
		notify("[mdview] detach: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	local root = detached.plugin_root()
	local init = root .. "/scripts/minimal_init.lua"
	if vim.fn.filereadable(init) ~= 1 then
		notify("[mdview] detach: minimal init not found at " .. init, vim.log.levels.ERROR)
		return
	end

	-- v:progpath is this instance's own nvim binary, so the detached instance is
	-- guaranteed to be the same build — not whatever unrelated `nvim` happens to
	-- be first on PATH.
	local nvim = vim.v.progpath
	local args = {
		"--headless",
		"-u", init,
		"-c", "MDView start",
		target,
	}

	-- minimal_init.lua reads these; passing them through the child's environment
	-- rather than as more -c commands keeps the command line stable and avoids
	-- quoting a Lua expression through two layers of process spawning.
	local env = { MDVIEW_PATH = root }
	if no_browser then
		env.MDVIEW_NO_BROWSER = "1"
	end

	local pid, spawn_err = detached.spawn(nvim, args, vim.fn.getcwd(), env)
	if not pid then
		notify("[mdview] detach: failed to spawn Neovim: " .. tostring(spawn_err), vim.log.levels.ERROR)
		return
	end

	log.debug(("detach: spawned pid %d for %s"):format(pid, target), nil, "usercmds.detach", true)
	notify(
		("[mdview] detached preview started (pid %d) for %s\nIt outlives this instance — stop it by closing the preview tab, or kill the pid.")
			:format(pid, vim.fn.fnamemodify(target, ":t")),
		vim.log.levels.INFO
	)
end

return M

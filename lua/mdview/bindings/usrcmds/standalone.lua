---@module 'mdview.bindings.usrcmds.standalone'
--- Action behind :MDView standalone — hand a file to the relay binary's own
--- watch mode and step out of the way entirely.
---
--- Unlike :MDView detach (which starts a second *Neovim*), this leaves no
--- Neovim in the chain at all: the relay watches the file on disk itself and
--- broadcasts changes straight to the browser. The trade-off is the point —
---
---   detach     : full mdview (live buffer push, scroll sync, cursor marker,
---                click-navigate), because a real Neovim is driving it.
---   standalone : file-on-disk only. No unsaved-buffer preview, no scroll sync,
---                no cursor marker — nothing that requires knowing where a
---                cursor is. In exchange it costs one small process and keeps
---                running no matter what happens to any editor.
---
--- Use it for a reference document you want open beside your work, or to share
--- a rendered doc with something that isn't Neovim.

local detached = require("mdview.adapter.detached")
local install = require("mdview.adapter.install")
local log = require("mdview.helper.log")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

--- Does `bin` understand --watch?
---
--- Worth checking before spawning: standalone mode needs a relay built with
--- watch support (v0.3.0+), but the binary on disk is whatever `install.version`
--- pinned. An older one rejects the flag and exits instantly — and since a
--- detached process has no pipes, that failure is completely silent. Probing
--- turns "nothing happened, no idea why" into an actionable message.
---
--- Go's flag package prints its usage (which lists every defined flag) to
--- stderr and exits non-zero for an unknown flag, so an unknown-flag probe is
--- itself the capability check.
---@param bin string
---@return boolean
local function supports_watch(bin)
	local out = vim.fn.system({ bin, "--mdview-capability-probe" })
	return type(out) == "string" and out:find("-watch", 1, true) ~= nil
end

--- The relay binary to use for standalone mode: an explicit
--- `standalone.binary_path` override if configured (for a locally built relay,
--- or a newer one than `install.version` pins), else the installed release.
---@return string|nil path, string|nil err
local function resolve_binary()
	local cfg = require("mdview.config").defaults.standalone or {}
	local override = cfg.binary_path
	if type(override) == "string" and override ~= "" then
		local path = vim.fn.expand(override)
		if vim.fn.executable(path) ~= 1 then
			return nil, "standalone.binary_path is not executable: " .. path
		end
		return path, nil
	end
	return install.ensure_binary()
end

--- Start the relay in standalone watch mode for `file` (default: the current
--- buffer's file).
---   :MDView standalone
---   :MDView standalone notes.md
---   :MDView standalone notes.md --no-browser
---@param file_arg string|nil # path from the route's `file` arg
---@param no_browser boolean|nil # true when --no-browser was passed
function M.run(file_arg, no_browser)
	local target, err = detached.resolve_target(file_arg)
	if not target then
		notify("[mdview] standalone: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	-- Standalone previews the file as it is *on disk*. Warning here rather than
	-- silently previewing stale content is the honest thing: the user asked for
	-- this file and would otherwise wonder why their edits don't show up.
	if vim.bo.modified and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p") == target then
		notify(
			"[mdview] standalone previews the file on disk — unsaved changes in this buffer won't appear until you :write",
			vim.log.levels.WARN
		)
	end

	local bin, bin_err = resolve_binary()
	if not bin then
		notify("[mdview] standalone: " .. tostring(bin_err), vim.log.levels.ERROR)
		return
	end

	if not supports_watch(bin) then
		notify(
			("[mdview] standalone: this relay binary has no --watch support.\n%s\nIt needs mdview-server v0.3.0+. Either bump install.version, or point standalone.binary_path at a newer/locally built relay.")
				:format(bin),
			vim.log.levels.ERROR
		)
		return
	end

	local web_root, web_err = install.ensure_client_bundle()
	if not web_root then
		notify("[mdview] standalone: " .. tostring(web_err), vim.log.levels.ERROR)
		return
	end

	local defaults = require("mdview.config").defaults
	local browser_defaults = require("mdview.config.browser").defaults

	-- Generate the token here rather than letting the relay mint its own: a
	-- detached process's stdout goes nowhere, so if the relay chose the token we
	-- could never tell the user the preview URL. That matters for --no-browser,
	-- whose whole point is opening the preview yourself (or from another device).
	local token = require("mdview.helper.gen_token")()
	local port = (defaults.server_port or 43219) + 100
	local theme = tostring(browser_defaults.theme or "github")
	local highlighter = tostring(browser_defaults.highlighter or "hljs")

	local args = {
		"--watch", target,
		"--token", token,
		"--web-root", web_root,
		-- Offset well clear of both server_port and dev_server_port
		-- (server_port + 1 by default): a standalone preview is meant to sit
		-- alongside a normal session, so it must not compete for the relay's
		-- port, nor land on the Vite dev port during development. The relay's
		-- FindFreePort still walks upward from here if this one is taken.
		"--port", tostring(port),
		"--theme", theme,
		"--hl", highlighter,
	}
	if no_browser then
		args[#args + 1] = "--open=false"
	end

	local pid, spawn_err = detached.spawn(bin, args, vim.fn.fnamemodify(target, ":h"))
	if not pid then
		notify("[mdview] standalone: failed to spawn relay: " .. tostring(spawn_err), vim.log.levels.ERROR)
		return
	end

	local url = ("http://localhost:%d/?key=%s&token=%s&theme=%s&hl=%s"):format(
		port,
		require("mdview.helper.normalize").path_for_url(target),
		vim.uri_encode(token),
		vim.uri_encode(theme),
		vim.uri_encode(highlighter)
	)

	log.debug(("standalone: spawned pid %d for %s at %s"):format(pid, target, url), nil, "usercmds.standalone", true)

	local msg = ("[mdview] standalone preview started (pid %d) for %s\nNo Neovim involved — it follows the file on disk. Stop it by killing the pid.")
		:format(pid, vim.fn.fnamemodify(target, ":t"))
	if no_browser then
		-- Nothing opened a tab, so the URL is the only way in. Port is the
		-- requested one; the relay walks upward if it was taken.
		msg = msg .. ("\nOpen: %s\n(if port %d was taken, the relay picked the next free one)"):format(url, port)
	end
	notify(msg, vim.log.levels.INFO)
end

return M

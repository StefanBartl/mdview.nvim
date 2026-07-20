---@module 'mdview.bindings.usrcmds'
--- Registers the unified :MDView <subcommand> user command via
--- lib.nvim.usercmd.composer — one route tree drives dispatch, <Tab>
--- completion, and (via composer.document()) a Markdown command reference, so
--- the ten formerly-separate :MDViewX commands can't drift out of sync with
--- their own docs. See docs/commands.md for the generated-by-hand reference
--- and docs/ROADMAP (lib.nvim) for the composer's design.
---
--- All user commands are registered once at setup() and never torn down —
--- they are the plugin's permanent command surface (like every other Neovim
--- plugin's :Commands), not something to attach/detach per preview session.
--- Only autocommands (mdview.bindings.autocmds) have a real attach/detach
--- lifecycle, since those genuinely need to stop firing once a session ends.

local composer = require("lib.nvim.usercmd.composer")

local start = require("mdview.bindings.usrcmds.start")
local stop = require("mdview.bindings.usrcmds.stop")
local open = require("mdview.bindings.usrcmds.open")
local toggle = require("mdview.bindings.usrcmds.toggle")
local show_weblogs = require("mdview.bindings.usrcmds.show_weblogs")
local preview_tab = require("mdview.bindings.usrcmds.preview_tab")
local diagnose = require("mdview.bindings.usrcmds.diagnose")
local theme = require("mdview.bindings.usrcmds.theme")
local log = require("mdview.bindings.usrcmds.log")
local file_log = require("mdview.bindings.usrcmds.file_log")
local cursor = require("mdview.bindings.usrcmds.cursor")
local sync = require("mdview.bindings.usrcmds.sync")
local zoom = require("mdview.bindings.usrcmds.zoom")
local reveal = require("mdview.bindings.usrcmds.reveal")
local breadcrumbs = require("mdview.bindings.usrcmds.breadcrumbs")
local overlay = require("mdview.bindings.usrcmds.overlay")

local M = {}

--- `log <level>` routes, one per known level (trace|debug|info|warn|error),
--- generated from log.LEVELS so the route list can't drift from the filter it
--- drives.
---@return Lib.UserCmd.Composer.Route[]
local function log_level_routes()
	local routes = {}
	for name, level in pairs(log.LEVELS) do
		routes[#routes + 1] = {
			path = { "log", name },
			desc = ("Show the internal log ring, filtered to %s and above"):format(name:upper()),
			run = function() log.show_ring(level) end,
		}
	end
	table.sort(routes, function(a, b) return a.path[2] < b.path[2] end)
	return routes
end

---@return nil
function M.attach()
	local routes = {
		{ path = { "start" },
			desc = "Start the relay and open the preview for the current buffer (or the given file)",
			run  = function(ctx) start.run(ctx.rest) end },

		{ path = { "stop" },
			desc = "Stop the relay, detach autocommands, and (in isolated mode) close the browser",
			run  = function() stop.run() end },

		{ path = { "toggle" },
			desc = "Start if stopped, stop if running",
			run  = function(ctx) toggle.run(ctx.rest) end },

		{ path = { "open" },
			desc = "Re-open a browser tab against the already-running session",
			run  = function() open.run() end },

		{ path = { "weblogs" },
			desc = "Show the relay's captured stdout, including [client] browser-side diagnostics",
			run  = function() show_weblogs.run() end },

		{ path = { "preview-tab" },
			desc = "Toggle the in-Neovim tab preview (works standalone, no server needed)",
			run  = function() preview_tab.run() end },

		{ path = { "diagnose" },
			args = { { name = "path", type = "PATH", optional = true } },
			desc = "Write a full component-state diagnostics report to a file and open it",
			run  = function(ctx) diagnose.run(ctx.args.path) end },

		{ path = { "theme" },
			args = { { name = "name", type = "STRING", optional = true, values = theme.known } },
			desc = "Switch the preview theme (optionally -light/-dark); no argument reports the current theme",
			run  = function(ctx) theme.run(ctx.args.name) end },

		{ path = { "log" },
			desc = "Show the internal log ring",
			run  = function() log.show_ring(nil) end },
		{ path = { "log", "export" },
			args = { { name = "path", type = "PATH", optional = true } },
			desc = "Write the internal log ring to a file (default: stdpath log)",
			run  = function(ctx) log.export_ring(ctx.args.path) end },

		{ path = { "file-log" },
			desc = "Toggle persistent file logging, then report the state",
			run  = function() file_log.toggle() end },
		{ path = { "file-log", "on" },
			args = { { name = "path", type = "PATH", optional = true } },
			desc = "Enable persistent file logging (optionally set its path)",
			run  = function(ctx) file_log.on(ctx.args.path) end },
		{ path = { "file-log", "off" },
			desc = "Disable persistent file logging",
			run  = function() file_log.off() end },
		{ path = { "file-log", "toggle" },
			desc = "Toggle persistent file logging, then report the state",
			run  = function() file_log.toggle() end },
		{ path = { "file-log", "status" },
			desc = "Report persistent file logging state without changing anything",
			run  = function() file_log.status() end },
		{ path = { "file-log", "path" },
			args = { { name = "value", type = "PATH", optional = true } },
			desc = "Set the file log path (or `default` to reset it); omit to report the current path",
			run  = function(ctx) file_log.path(ctx.args.value) end },

		-- Live preview controls: each pushes a control update to the open tab
		-- (no reload) and records the choice for the next start.
		{ path = { "cursor" },
			args = { { name = "mode", type = "STRING", optional = true, values = cursor.modes } },
			desc = "Set the Neovim-cursor marker in the preview (line|caret|section|off)",
			run  = function(ctx) cursor.run(ctx.args.mode) end },

		{ path = { "sync" },
			args = { { name = "action", type = "STRING", optional = true, values = sync.actions } },
			desc = "Pause/resume the nvim->browser scroll sync; no argument reports the state",
			run  = function(ctx) sync.run(ctx.args.action) end },

		{ path = { "zoom" },
			args = { { name = "step", type = "STRING", optional = true, values = zoom.actions } },
			desc = "Adjust the preview font-size zoom (+ | - | reset | <factor>)",
			run  = function(ctx) zoom.run(ctx.args.step) end },

		{ path = { "reveal" },
			args = { { name = "action", type = "STRING", optional = true, values = reveal.actions } },
			desc = "Reveal/hide all private (```private) blocks in the preview",
			run  = function(ctx) reveal.run(ctx.args.action) end },

		{ path = { "overlay" },
			args = {
				{ name = "name", type = "STRING", optional = true, values = overlay.names() },
				{ name = "action", type = "STRING", optional = true, values = { "on", "off", "toggle" } },
			},
			desc = "Toggle a preview overlay (floating TOC, …); no name lists them",
			run  = function(ctx) overlay.run(ctx.args.name, ctx.args.action) end },
		{ path = { "overlay", "list" },
			desc = "List the known preview overlays and whether each is on",
			run  = function() overlay.list() end },

		{ path = { "breadcrumbs" },
			desc = "Show the session breadcrumbs (document + heading over time)",
			run  = function() breadcrumbs.show() end },
		{ path = { "breadcrumbs", "export" },
			args = { { name = "path", type = "PATH", optional = true } },
			desc = "Write the session breadcrumbs outline to a file (default: stdpath log)",
			run  = function(ctx) breadcrumbs.export(ctx.args.path) end },
		{ path = { "breadcrumbs", "clear" },
			desc = "Discard the recorded session breadcrumbs",
			run  = function() breadcrumbs.clear() end },
	}

	vim.list_extend(routes, log_level_routes())

	composer.verb("MDView", {
		desc   = "mdview.nvim commands",
		routes = routes,
	})
end

return M

---@module 'mdview.health'
-- :checkhealth support for mdview.nvim.
--
-- The relay server and client bundle are native, prebuilt assets downloaded
-- once from GitHub Releases (see mdview.adapter.install) — there is no
-- Node/Go/Rust toolchain requirement for end users anymore. This check only
-- verifies the tools install.lua needs to fetch and verify those assets
-- (curl, tar), and reports whether they're already cached, without
-- triggering a download itself.

local M = {}

-- vim.health.start/ok/warn/error replaced the report_* names in Neovim 0.10;
-- fall back to the older names so :checkhealth still works on 0.9.
local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error_ = health.error or health.report_error

---@param cmd string
---@return boolean
local function executable(cmd)
	return vim.fn.executable(cmd) == 1
end

function M.check()
	start("mdview.nvim: environment")

	if vim.fn.has("nvim-0.9") == 1 then
		ok("Neovim >= 0.9")
	else
		error_("Neovim >= 0.9 is required")
	end

	-- lib.nvim is a HARD dependency: mdview requires it for cross-platform
	-- helpers (is_windows, path separators), user-command registration, and
	-- structured logging. Missing it is an error, not a warning — the plugin
	-- cannot function without it. Probe one representative module rather than
	-- the bare namespace so a half-installed lib.nvim is also caught.
	if pcall(require, "lib.nvim.cross.platform.is_windows") then
		ok("lib.nvim found (required cross-platform / logging / usercmd library)")
	else
		error_(
			"lib.nvim not found — it is a required dependency. "
				.. "Add \"StefanBartl/lib.nvim\" to your plugin manager's dependencies (see README)."
		)
	end

	if executable("curl") then
		ok("curl found (used to download the mdview-server release on first use)")
	else
		error_("curl not found in PATH — mdview.nvim cannot download the relay server binary or client bundle")
	end

	if executable("tar") then
		ok("tar found (used to extract the client bundle)")
	else
		error_("tar not found in PATH — mdview.nvim cannot extract the downloaded client bundle")
	end

	start("mdview.nvim: installed assets")

	local install = require("mdview.adapter.install")
	local status = install.status()

	if status.binary_installed then
		ok("mdview-server binary cached at " .. status.binary_path)
	else
		warn("mdview-server binary not yet installed — will be downloaded on first `:MDViewStart`")
	end

	if status.client_installed then
		ok("client bundle cached at " .. status.client_dir)
		-- A present-but-incomplete bundle (e.g. an interrupted extract) fails
		-- silently at render time with a blank page; surface it here instead.
		local dir = status.client_dir
		local has_index = vim.fn.filereadable(dir .. "/index.html") == 1
		local wasm = vim.fn.glob(dir .. "/assets/*.wasm", true, true)
		if has_index and #wasm > 0 then
			ok("client bundle looks complete (index.html + WASM present)")
		else
			error_(
				"client bundle at "
					.. dir
					.. " is incomplete ("
					.. (has_index and "" or "index.html missing; ")
					.. (#wasm > 0 and "" or "no .wasm in assets/; ")
					.. "delete the cache dir and re-run :MDViewStart to re-download)"
			)
		end
	else
		warn("client bundle not yet installed — will be downloaded on first `:MDViewStart`")
	end

	-- Config & opt-in features ------------------------------------------------
	start("mdview.nvim: configuration")

	local defaults = require("mdview.config").defaults
	ok(("open_mode = %q, theme = %q, scroll_sync = %s, open_preview_tab = %s"):format(
		tostring(defaults.browser and defaults.browser.open_mode),
		tostring(defaults.browser and defaults.browser.theme),
		tostring(defaults.scroll_sync),
		tostring(defaults.open_preview_tab)
	))

	local exp = defaults.experimental or {}
	local enabled = {}
	for _, flag in ipairs({ "line_diff", "click_navigate", "reverse_scroll", "webtransport" }) do
		if exp[flag] == true then
			enabled[#enabled + 1] = flag
		end
	end
	if #enabled > 0 then
		ok("experimental features on: " .. table.concat(enabled, ", "))
	else
		ok("no experimental features enabled (all opt-in flags off)")
	end

	-- Browser resolution ------------------------------------------------------
	local bcfg = require("mdview.config.browser")
	local resolved = bcfg.defaults.resolved_browser_cmd
	if defaults.browser and defaults.browser.open_mode == "isolated" then
		if resolved and resolved ~= "" then
			ok("browser resolved (isolated mode): " .. resolved)
		else
			warn("open_mode = \"isolated\" but no browser resolved — set browser.browser_cmd or browser.browser")
		end
	else
		ok("open_mode = \"default\" — uses the OS opener (no browser executable needed)")
	end

	if defaults.browser and defaults.browser.require_display then
		local has_display = (vim.fn.has("gui_running") == 1)
			or (vim.env.DISPLAY ~= nil)
			or (vim.env.WAYLAND_DISPLAY ~= nil)
			or (vim.fn.has("win32") == 1)
			or (vim.fn.has("mac") == 1)
		if has_display then
			ok("a GUI/display is available for browser autostart")
		else
			warn("no DISPLAY/WAYLAND_DISPLAY detected — browser autostart is skipped (set browser.require_display = false to override)")
		end
	end

	-- Running session ---------------------------------------------------------
	start("mdview.nvim: session")

	local state = require("mdview.core.state")
	if state.proc_is_running() then
		local port = vim.g.mdview_server_port or defaults.server_port
		local body
		if executable("curl") then
			body = vim.fn.system({ "curl", "-sS", "--max-time", "2", ("http://127.0.0.1:%d/health"):format(port) })
			body = (body or ""):gsub("%s+$", "")
		end
		if body == "ok" then
			ok(("relay running on port %d and healthy (GET /health = ok)"):format(port))
		else
			warn(("relay process is up on port %d but /health did not return ok (got %q)"):format(port, tostring(body)))
		end
		ok("attached = " .. tostring(state.is_attached()) .. ", session token set = " .. tostring(state.get_token() ~= nil))
	else
		ok("no relay session running (start one with :MDViewStart)")
	end

	-- Companion plugins (optional, not dependencies) --------------------------
	start("mdview.nvim: optional companions")

	local function has_plugin(mod)
		return pcall(require, mod)
	end
	-- markdown.nvim edits the buffer TEXT (TOC, refs, tables) — mdview mirrors
	-- that live into the preview for free, so it pairs well but is not required.
	if has_plugin("markdown") then
		ok("markdown.nvim detected — its buffer edits (TOC/refs/tables) mirror into the preview automatically")
	else
		ok("markdown.nvim not installed (optional companion — buffer-text features would mirror into the preview)")
	end
	-- color_my_ascii highlights in the nvim buffer (not HTML), so it complements
	-- rather than feeds the browser preview.
	if has_plugin("color_my_ascii") then
		ok("color_my_ascii.nvim detected (highlights code in the nvim buffer; browser highlighting is separate)")
	else
		ok("color_my_ascii.nvim not installed (optional; highlights fenced code inside Neovim)")
	end
end

return M

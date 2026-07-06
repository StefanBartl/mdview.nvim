---@module 'mdview.config.DEFAULTS'
--- Single source of truth for mdview.nvim's default configuration.
--- Kept separate from config/init.lua so "what the defaults are" and "how
--- setup() merges user overrides into them" stay decoupled.
---
--- mdview.config.browser and mdview.config.usrcmd_start don't duplicate this
--- data — they point their own `M.defaults` at the `browser`/`start`
--- sub-tables here (see those files), so there is exactly one copy of every
--- default value regardless of which module a caller requires it through.

---@class mdview.config.BrowserDefaults
---@field autodetect_browser boolean try to locate a browser automatically
---@field browser string friendly name e.g. "chrome" or "firefox"
---@field browser_cmd string absolute path to executable to force use
---@field browser_autoclose boolean whether :MDViewStop closes the controlled browser
---@field browser_autostart boolean whether to open the browser automatically on start
---@field resolved_browser_cmd string|nil internal, populated by config.browser.resolve_and_validate()
---@field browser_args string[]|nil extra CLI args for the resolved browser executable
---@field dev_server_port integer Vite dev server port, preferred over server_port when set and > 0
---@field open_url string|nil static override URL always used instead of the computed key/token URL
---@field require_display boolean don't auto-open a browser without a GUI/DISPLAY available (see mdview-security)
---@field stop_on_browser_exit boolean run :MDViewStop when the opened browser process exits (e.g. tab/window closed)

---@class mdview.config.StartDefaults
---@field push_strategy "launcher"|"try_push" initial-push strategy used by :MDViewStart
---@field try_push_opts table|nil forwarded to try_push when push_strategy == "try_push"
---@field wait_timeout_ms integer|nil forwarded to launcher.wait_ready

---@class mdview.config.InstallDefaults
---@field repo string GitHub "owner/repo" releases are downloaded from — override if you run a fork
---@field version string release tag to install (e.g. "v0.1.0") — pin an older release by changing this

---@class mdview.config.Defaults
---@field ft_pattern string[] filetype/glob patterns mdview's autocmds attach to
---@field server_port integer preferred port the relay server listens on
---@field server_cwd string|nil optional explicit working directory for the relay process
---@field dev_local boolean developer-only flag
---@field debug boolean when true, print server stdout/stderr into Neovim (dev only)
---@field log_buffer_name string scratch buffer name used to show logs when debug=true
---@field debug_plugin boolean enable plugin-internal debug notifications
---@field debug_preview boolean enable live-push debug notifications
---@field dev_server_port integer Vite dev server port for client (dev workflow only)
---@field scroll_sync boolean send cursor position to the browser preview so it scrolls to follow (nvim-to-browser only)
---@field scroll_sync_throttle_ms integer minimum time between scroll-position pings
---@field browser mdview.config.BrowserDefaults
---@field start mdview.config.StartDefaults
---@field install mdview.config.InstallDefaults

---@type mdview.config.Defaults
return {
	ft_pattern = { ".markdown", "*.md", "*.mdx" },

	server_port = 43219,
	server_cwd = nil,

	dev_local = true,
	debug = true,
	log_buffer_name = "mdview://logs",

	debug_plugin = true,
	debug_preview = true,

	dev_server_port = 43220,

	scroll_sync = true,
	scroll_sync_throttle_ms = 150,

	browser = {
		autodetect_browser = true,
		browser = "",
		browser_cmd = "",
		browser_autoclose = true,
		browser_autostart = true,
		resolved_browser_cmd = nil,
		browser_args = nil,
		dev_server_port = 43220,
		open_url = nil,
		require_display = true,
		stop_on_browser_exit = true,
	},

	start = {
		push_strategy = "launcher",
		try_push_opts = nil,
		wait_timeout_ms = nil,
	},

	install = {
		repo = "StefanBartl/mdview.nvim",
		version = "v0.1.0",
	},
}

---@module 'mdview.config.DEFAULTS'
--- Single source of truth for mdview.nvim's default configuration.
--- Kept separate from config/init.lua so "what the defaults are" and "how
--- setup() merges user overrides into them" stay decoupled.
---
--- mdview.config.browser and mdview.config.usrcmd_start don't duplicate this
--- data — they point their own `M.defaults` at the `browser`/`start`
--- sub-tables here (see those files), so there is exactly one copy of every
--- default value regardless of which module a caller requires it through.

---@alias mdview.config.BrowserOpenMode
---| '"default"' # open in your normal default browser as a new tab (your extensions/theme; no programmatic close)
---| '"isolated"' # spawn a separate mdview browser profile/window (auto-close works; no access to your extensions)

---@class mdview.config.BrowserDefaults
---@field open_mode mdview.config.BrowserOpenMode how the preview browser is opened (default "default")
---@field autodetect_browser boolean try to locate a browser automatically (isolated mode only)
---@field browser string friendly name e.g. "chrome" or "firefox" (isolated mode only)
---@field browser_cmd string absolute path to executable to force use (isolated mode only)
---@field browser_autoclose boolean whether :MDViewStop closes the controlled browser (isolated mode only)
---@field browser_autostart boolean whether to open the browser automatically on start
---@field resolved_browser_cmd string|nil internal, populated by config.browser.resolve_and_validate()
---@field browser_args string[]|nil extra CLI args for the resolved browser executable (isolated mode only)
---@field open_url string|nil static override URL always used instead of the computed key/token URL
---@field require_display boolean don't auto-open a browser without a GUI/DISPLAY available (see mdview-security)
---@field stop_on_browser_exit boolean run :MDViewStop when the opened browser process exits (isolated mode only)
---@field theme string preview theme passed to the client as ?theme= — one of "github", "dark-dimmed", "plain" (optionally suffixed "-light"/"-dark" to pin the color scheme); see src/client/themes/

---@class mdview.config.StartDefaults
---@field push_strategy "launcher"|"try_push" initial-push strategy used by :MDViewStart
---@field try_push_opts table|nil forwarded to try_push when push_strategy == "try_push"
---@field wait_timeout_ms integer|nil forwarded to launcher.wait_ready

---@class mdview.config.InstallDefaults
---@field repo string GitHub "owner/repo" releases are downloaded from — override if you run a fork
---@field version string release tag to install (e.g. "v0.1.0") — pin an older release by changing this

---@class mdview.config.ExperimentalDefaults
---@field webtransport boolean opt in to the WebTransport (HTTP/3) client transport; falls back to WebSocket until an HTTP/3 relay backend exists (future tech)

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
---@field open_preview_tab boolean :MDViewStart opens an nvim-tab preview (Treesitter-highlighted mirror, no browser/relay HTML) instead of the browser
---@field browser mdview.config.BrowserDefaults
---@field start mdview.config.StartDefaults
---@field install mdview.config.InstallDefaults
---@field experimental mdview.config.ExperimentalDefaults

---@type mdview.config.Defaults
return {
	ft_pattern = { ".markdown", "*.md", "*.mdx" },

	server_port = 43219,
	server_cwd = nil,

	dev_local = true,
	-- Debug flags are opt-in: with `debug = true` every relay stdout line is
	-- echoed into Neovim, and `debug_preview = true` notifies on every push
	-- (i.e. per keystroke). Enable via setup({ debug = true, ... }) when
	-- actually debugging.
	debug = false,
	log_buffer_name = "mdview://logs",

	debug_plugin = false,
	debug_preview = false,

	dev_server_port = 43220,

	scroll_sync = true,
	scroll_sync_throttle_ms = 150,

	open_preview_tab = false,

	browser = {
		open_mode = "default",
		autodetect_browser = true,
		browser = "",
		browser_cmd = "",
		browser_autoclose = true,
		browser_autostart = true,
		resolved_browser_cmd = nil,
		browser_args = nil,
		open_url = nil,
		require_display = true,
		stop_on_browser_exit = true,
		theme = "github",
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

	experimental = {
		-- Opt in to the WebTransport (HTTP/3) client transport instead of
		-- WebSocket. Future tech: the relay does not serve an HTTP/3 endpoint
		-- yet (see docs/Roadmap/WebTransportAPI/DESIGN.md), so enabling this
		-- currently makes the client feature-detect WebTransport, attempt it,
		-- and fall back to WebSocket transparently — never breaking the
		-- preview. Kept as an opt-in so the plumbing is ready when the backend
		-- lands. Default false.
		webtransport = false,
	},
}

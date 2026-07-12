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

---@alias mdview.config.BrowserBehavior
---| '"reuse"' # the one preview tab follows the active markdown buffer (default)
---| '"new_tab"' # each markdown buffer you switch to opens its own preview tab
---| '"manual"' # switching buffers does nothing; open other files with :MDViewOpen

---@class mdview.config.BrowserDefaults
---@field open_mode mdview.config.BrowserOpenMode how the preview browser is opened (default "default")
---@field behavior mdview.config.BrowserBehavior what happens to the preview when you switch markdown buffers (default "reuse")
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
---@field theme string preview theme passed to the client as ?theme= — one of "github", "dark-dimmed", "plain", "tokyonight", "catppuccin" (optionally suffixed "-light"/"-dark" to pin the color scheme); see src/client/themes/
---@field highlighter "hljs"|"shiki"|"none" code-fence syntax highlighter (client-side, lazy-loaded): "hljs" (light, default), "shiki" (exact VSCode/TextMate themes, heavier), or "none"
---@field focus "browser"|"nvim" whether the opened tab may take keyboard focus ("browser", default) or focus stays in Neovim ("nvim" — clean on macOS, best-effort on Windows, no-op on Linux); default open_mode only

---@class mdview.config.StartDefaults
---@field push_strategy "launcher"|"try_push" initial-push strategy used by :MDViewStart
---@field try_push_opts table|nil forwarded to try_push when push_strategy == "try_push"
---@field wait_timeout_ms integer|nil forwarded to launcher.wait_ready

---@class mdview.config.InstallDefaults
---@field repo string GitHub "owner/repo" releases are downloaded from — override if you run a fork
---@field version string release tag to install (e.g. "v0.1.0") — pin an older release by changing this

---@class mdview.config.ExperimentalDefaults
---@field webtransport boolean opt in to the WebTransport (HTTP/3) client transport; falls back to WebSocket until an HTTP/3 relay backend exists (future tech)
---@field line_diff boolean opt in to sending only changed lines per edit instead of the whole document (versioned diff transport; client reassembles full text)
---@field click_navigate boolean opt in to click-to-navigate: clicking a relative link in the preview opens the linked document in Neovim (via the relay's /nav bridge)
---@field reverse_scroll boolean opt in to reverse scroll: scrolling the preview moves Neovim's cursor to match (polled, so slightly lagged)

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
---@field scroll_sync_mode "top"|"cursor" where the cursor line lands in the browser viewport: near the top, or mirroring the cursor's height in the nvim window
---@field scroll_sync_top_offset number in "top" mode, fraction (0..1) down from the viewport top to place the line (0 = glued to top)
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
	-- Where the cursor line lands in the browser viewport:
	--   "top"    — near the top (scroll_sync_top_offset controls how far down,
	--              0 = glued to the very top).
	--   "cursor" — mirror Neovim: place the line at the same relative height as
	--              the cursor sits in the nvim window (middle stays middle).
	scroll_sync_mode = "top",
	scroll_sync_top_offset = 0.08,

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
		behavior = "reuse",
		highlighter = "hljs",
		focus = "browser",
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

		-- Opt in to the line-diff transport: send only the changed lines on each
		-- edit (versioned \x03 envelopes, client reassembles full text) instead
		-- of the whole document. Saves bandwidth on large files; rendering still
		-- processes the whole document client-side, so on loopback the win is
		-- modest. The default full-text push stays the verified path. On any
		-- diff desync the client resyncs from the next full snapshot (sent on
		-- save and every 25 edits). Default false.
		line_diff = false,

		-- Opt in to click-to-navigate: clicking a relative link in the preview
		-- tells Neovim (via the relay's /nav bridge, polled while a session is
		-- active) to open the linked document, which then flows back into the
		-- preview. Resolved relative to the source document; external links,
		-- in-page anchors and absolute paths are left to the browser. Changes
		-- how link clicks behave, so it's opt-in. Default false.
		click_navigate = false,

		-- Opt in to reverse scroll (browser -> Neovim): scrolling the preview
		-- moves Neovim's cursor to the matching position (the complement of the
		-- always-on nvim -> browser scroll_sync). Implemented by polling, so it
		-- follows with a small lag rather than instantly. Default false.
		reverse_scroll = false,
	},
}

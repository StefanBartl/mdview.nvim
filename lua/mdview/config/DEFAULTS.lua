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
---@field external_links "new_tab"|"same_tab" open external links (http/mailto/absolute) in a new tab ("new_tab", default — keeps the preview tab) or in place ("same_tab")
---@field cursor_marker "line"|"caret"|"section"|"off" show the Neovim cursor in the preview: line marker in the left gutter ("line", default), an exact caret at the cursor column ("caret", uses inline source-position spans), a spotlight on the current heading section with the rest dimmed ("section"), or hidden ("off"); rides the scroll-sync ping, so needs scroll_sync on
---@field zoom number preview font-size zoom factor (1.0 = 100%, default); adjust at runtime with :MDViewZoom, passed to the client as ?zoom= and pushed live
---@field overlays table<string, boolean> which preview overlays start enabled, e.g. { toc = false }; toggle at runtime with :MDViewOverlay, passed to the client as ?overlays= and pushed live
---@field preserve_blank_lines boolean show every blank line between blocks as extra vertical space instead of CommonMark's default (any run of blank lines collapses to one paragraph gap); off by default, toggle at runtime with `:MDView blanklines`, passed to the client as ?blanklines=1 and pushed live

---@class mdview.config.StartDefaults
---@field push_strategy "launcher"|"try_push" initial-push strategy used by :MDViewStart
---@field try_push_opts table|nil forwarded to try_push when push_strategy == "try_push"
---@field wait_timeout_ms integer|nil forwarded to launcher.wait_ready

---@class mdview.config.InstallDefaults
---@field repo string GitHub "owner/repo" releases are downloaded from — override if you run a fork
---@field version string release tag to install (e.g. "v0.1.0") — pin an older release by changing this

---@class mdview.config.StandaloneDefaults
---@field binary_path string|nil relay binary used by `:MDView standalone`; nil = the one `install` manages. Set this to run a locally built or newer relay than `install.version` pins (standalone needs --watch support, v0.3.0+)

---@class mdview.config.DevDefaults
---@field binary_path string|nil relay binary used by the normal `:MDView start` path; nil = the one `install` manages. Set this to run a locally built or newer relay than `install.version` pins — needed for e.g. overlay/zoom/cursor live-control (`/control` route), which postdates `install.version`'s default pin. Falls back to `$MDVIEW_DEV_BINARY` if unset (honored by `scripts/minimal_init.lua`'s detached instances, which don't load this Lua config).
---@field web_root string|nil prebuilt client bundle (HTML/JS/WASM) directory used by the normal `:MDView start` path; nil = the one `install` manages. Set this alongside `binary_path` when testing local relay+client changes together (e.g. `dist/client` from `npm run build`). Falls back to `$MDVIEW_DEV_WEB_ROOT` if unset.

---@class mdview.config.ExperimentalDefaults
---@field webtransport boolean opt in to the WebTransport (HTTP/3) client transport; falls back to WebSocket until an HTTP/3 relay backend exists (future tech)
---@field line_diff boolean opt in to sending only changed lines per edit instead of the whole document (versioned diff transport; client reassembles full text)
---@field click_navigate boolean opt in to click-to-navigate: clicking a relative link in the preview opens the linked document in Neovim (via the relay's /nav bridge)
---@field reverse_scroll boolean opt in to reverse scroll: scrolling the preview moves Neovim's cursor to match (polled, so slightly lagged)
---@field any_file boolean opt in to previewing any normal text buffer, not just Markdown: widens `ft_pattern` to `{"*"}` (see mdview.config.merge) and renders non-Markdown files as a syntax-highlighted read-only code view instead of through the Markdown renderer. Scroll-sync falls back to proportional (no per-line sourcepos yet). Takes precedence over a hand-set `ft_pattern`. Default false.

---@class mdview.config.Defaults
---@field ft_pattern string[] filetype/glob patterns mdview's autocmds attach to
---@field server_port integer preferred port the relay server listens on
---@field server_cwd string|nil optional explicit working directory for the relay process
---@field dev_local boolean developer-only flag
---@field debug boolean when true, print server stdout/stderr into Neovim (dev only)
---@field log_buffer_name string scratch buffer name used to show logs when debug=true
---@field file_log boolean opt in to writing the relay's stdout to a persistent log file (default false — nothing is written to disk); toggle at runtime with :MDViewFileLog
---@field file_log_path string|nil where the persistent log is written when file_log=true; defaults to `stdpath("log")/mdview/relay-<timestamp>.log` (never the cwd)
---@field debug_plugin boolean enable plugin-internal debug notifications
---@field debug_preview boolean enable live-push debug notifications
---@field dev_server_port integer Vite dev server port for client (dev workflow only)
---@field live_push_throttle_ms integer minimum time between full-buffer pushes on TextChanged/TextChangedI (each push spawns a curl process; rapid edits within the window coalesce into one trailing push instead of one per keystroke — see :MDView start vs standalone CPU benchmark in DONE.md). BufWritePost's save-triggered full push is never throttled.
---@field scroll_sync boolean send cursor position to the browser preview so it scrolls to follow (nvim-to-browser only)
---@field scroll_sync_throttle_ms integer minimum time between scroll-position pings
---@field scroll_sync_mode "top"|"cursor" where the cursor line lands in the browser viewport: near the top, or mirroring the cursor's height in the nvim window
---@field scroll_sync_top_offset number in "top" mode, fraction (0..1) down from the viewport top to place the line (0 = glued to top)
---@field sync_checkboxes boolean let ticking a GFM task-list checkbox in the preview write back to the source: standalone rewrites the file directly, :MDView start edits the buffer (polled, since Neovim has no WebSocket client). Default true; set false to render checkboxes read-only and stop the browser->Neovim poll
---@field sync_fields boolean let editing a raw-HTML text field (`<input name=…>` / `<textarea name=…>`) in the preview write its value back to the source, matched by the `name` attribute (raw HTML has no source position). Standalone rewrites the file, :MDView start edits the buffer (polled). Default true; set false to render such fields read-only
---@field breadcrumbs boolean record session breadcrumbs (which document + heading section over time) for :MDViewBreadcrumbs (default true)
---@field open_preview_tab boolean :MDViewStart opens an nvim-tab preview (Treesitter-highlighted mirror, no browser/relay HTML) instead of the browser
---@field browser mdview.config.BrowserDefaults
---@field start mdview.config.StartDefaults
---@field install mdview.config.InstallDefaults
---@field dev mdview.config.DevDefaults
---@field standalone mdview.config.StandaloneDefaults
---@field experimental mdview.config.ExperimentalDefaults
---@field deps_popup boolean show the lib.nvim.deps "declared tools" popup once, ever, on first setup() after install (default true; needs lib.nvim.deps — a no-op without it)
---@field transport mdview.config.TransportDefaults

--- Timing against the relay process. One block, because these are one
--- decision -- how patient to be with a relay that is slow to answer -- and
--- raising the retry count without the timeout just means retrying inside a
--- window that already expired.
---@class mdview.config.TransportDefaults
---@field health_poll_ms integer how often the relay is polled while waiting for it to come up (default 200)
---@field health_timeout_ms integer total wait for the relay to become healthy (default 10000)
---@field max_retries integer retry attempts for a single message (default 5)
---@field base_retry_ms integer initial retry delay; backs off exponentially from here (default 150)
---@field inbound_poll_ms integer how often the browser is polled for checkbox/field/navigate events (default 250)

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

  -- Persistent file logging is opt-in: with `file_log = false` (the default)
  -- mdview never touches the disk, so starting a preview no longer creates a
  -- `logs/` directory in whatever the cwd happens to be. Turn it on via
  -- setup({ file_log = true }) or at runtime with :MDViewFileLog on.
  file_log = false,
  -- nil -> stdpath("log")/mdview/relay-<timestamp>.log (resolved lazily, so
  -- the file is only created once file logging is actually enabled).
  file_log_path = nil,

  debug_plugin = false,
  debug_preview = false,

  dev_server_port = 43220,

  live_push_throttle_ms = 150,

  -- Timing against the relay process. The defaults suit a local relay on a
  -- normal machine; a first-run binary being scanned by antivirus, a busy CI
  -- box, or a relay over a slow link all want more of every one of them.
  transport = {
    health_poll_ms = 200,
    health_timeout_ms = 10000,
    max_retries = 5,
    base_retry_ms = 150,
    inbound_poll_ms = 250,
  },

  scroll_sync = true,
  scroll_sync_throttle_ms = 150,
  -- Where the cursor line lands in the browser viewport:
  --   "top"    — near the top (scroll_sync_top_offset controls how far down,
  --              0 = glued to the very top).
  --   "cursor" — mirror Neovim: place the line at the same relative height as
  --              the cursor sits in the nvim window (middle stays middle).
  scroll_sync_mode = "top",
  scroll_sync_top_offset = 0.08,

  breadcrumbs = true,

  -- Ticking a task-list checkbox in the preview writes `[ ]`<->`[x]` back to
  -- the source. Standalone rewrites the file directly (in the relay); :MDView
  -- start edits the buffer, which — since Neovim has no WebSocket client —
  -- needs the browser->Neovim poll (inbound_poll) running. Default on; set
  -- false to keep checkboxes read-only and avoid that poll in start mode.
  sync_checkboxes = true,

  -- Editing a raw-HTML text field (`<input name="x">` / `<textarea
  -- name="y">`) in the preview writes its value back to the source, located
  -- by the `name` attribute (raw HTML carries no source position, so unlike
  -- checkboxes there is no line to target — the name is the anchor).
  -- Standalone rewrites the file; :MDView start edits the buffer via the same
  -- browser->Neovim poll. Default on; false renders such fields read-only.
  sync_fields = true,

  open_preview_tab = false,

  -- One-time "which CLI tools does this plugin want, and why" popup on
  -- first setup() after install (via lib.nvim.deps). false disables it
  -- for this plugin specifically, right here in the spec passed to
  -- setup() — no vim.g needed. See README "Requirements".
  deps_popup = true,

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
    external_links = "new_tab",
    cursor_marker = "line",
    zoom = 1.0,
    -- Preview overlays (see :MDViewOverlay). Off by default — they're for
    -- presenting/screen-sharing, not for everyday editing.
    overlays = {
      toc = false,
    },
    -- Off by default: CommonMark's own behavior (any run of blank lines
    -- collapses to one paragraph gap) is what most people expect. See
    -- :MDView blanklines.
    preserve_blank_lines = false,
  },

  start = {
    push_strategy = "launcher",
    try_push_opts = nil,
    wait_timeout_ms = nil,
  },

  install = {
    repo = "StefanBartl/mdview.nvim",
    version = "v0.3.0",
  },

  dev = {
    -- Relay binary + client bundle `:MDView start` uses. nil = whatever
    -- `install` resolves (downloaded/cached from GitHub Releases). Set both
    -- to test a locally built relay/client, e.g.
    --   dev = {
    --     binary_path = "~/repos/mdview.nvim/native/server/mdview-server",
    --     web_root    = "~/repos/mdview.nvim/dist/client",
    --   }
    -- `npm run build:go` writes that name literally — no .exe on Windows —
    -- and `web_root` needs `npm run build` (wasm-pack + vite) to exist.
    -- Neither falls back to the release if the path is missing.
    -- Falls back to $MDVIEW_DEV_BINARY / $MDVIEW_DEV_WEB_ROOT when unset —
    -- the only way to reach a detached instance (scripts/minimal_init.lua
    -- loads none of this Lua config), since those are real OS env vars
    -- inherited by the spawned child rather than Lua-level state.
    binary_path = nil,
    web_root = nil,
  },

  standalone = {
    -- Relay binary `:MDView standalone` spawns. nil = whatever `install`
    -- resolved. Standalone mode needs a relay with --watch support
    -- (v0.3.0+); until `install.version` points at such a release, set this
    -- to a locally built one, e.g.
    --   standalone = { binary_path = "~/repos/mdview.nvim/native/server/mdview-server" }
    -- :MDView standalone probes the binary and says so if it's too old,
    -- rather than spawning a process that dies silently.
    binary_path = nil,
  },

  experimental = {
    -- Opt in to the WebTransport (HTTP/3) client transport instead of
    -- WebSocket. When on, the relay also serves a /wt endpoint (HTTP/3 over
    -- UDP on the same port, self-signed cert pinned via the printed hash)
    -- and the client tries WebTransport first, falling back to WebSocket on
    -- any failure — so it never breaks the preview. On loopback there is no
    -- real benefit over WebSocket; kept as opt-in "future tech". Requires a
    -- relay binary built with WebTransport support (v0.2.0+). Default false.
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
    -- how link clicks behave. On by default (relative links to other docs
    -- should open them); set false to let the browser follow links itself.
    click_navigate = true,

    -- Opt in to reverse scroll (browser -> Neovim): scrolling the preview
    -- moves Neovim's cursor to the matching position (the complement of the
    -- always-on nvim -> browser scroll_sync). Implemented by polling, so it
    -- follows with a small lag rather than instantly. Default false.
    reverse_scroll = false,

    -- Opt in to previewing any normal text buffer, not just Markdown. When
    -- true, mdview.config.merge() widens `ft_pattern` to `{"*"}` so every
    -- autocmd that drives the preview fires for any named, normal-buftype
    -- buffer (see helper/previewable.lua for the actual gate); the client
    -- renders non-Markdown documents as a syntax-highlighted read-only code
    -- view (extension -> language, see src/client/highlight/languageForPath.ts)
    -- instead of through the Markdown WASM renderer. Scroll-sync falls back
    -- to proportional positioning for these files (no per-line sourcepos yet,
    -- so the cursor line-bar doesn't show). Default false.
    any_file = false,
  },
}

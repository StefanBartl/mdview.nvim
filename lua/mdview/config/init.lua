---@module 'mdview.config'
--- Default configuration for mdview.nvim.
--- Contains developer-oriented options (server command + args) and tunables.
--- Users can override via require('mdview').setup({ ... }) in future.

local M = {}

-- Default developer-friendly values. These are safe defaults for most systems.
-- server_cmd defaults to "npm" so that "npm run dev:server" is used.
M.defaults = {
	-- filetype extension patterns for commands (audit: consider supporting filetype names too)
	ft_pattern = { ".markdown", "*.md", "*.mdx" },

	server_cmd = "npm",
	server_args = { "run", "dev" },
	server_port = 43219,
	-- optional explicit working directory for the server (useful in editor contexts)
	server_cwd = nil,

	-- send_diffs controls whether the client attempts to compute and send diffs
	send_diffs = false,

	-- developer-only flags can live here
	dev_local = true,
	-- when true, print server stdout/stderr into Neovim (dev only)
	debug = true,
	-- name for the scratch buffer used to show logs when debug=true
	log_buffer_name = "mdview://logs",

	debug_plugin = true,
	debug_preview = true,

	-- development helper: Vite dev server port for client (launcher resolves dev vs backend)
	-- set to 0 or nil when not using dev server
	dev_server_port = 43220,
}

return M

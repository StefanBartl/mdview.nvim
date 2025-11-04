---@module 'mdview.config'
--- Default configuration for mdview.nvim.
--- Contains developer-oriented options (server command + args) and tunables.
--- Users can override via require('mdview').setup({ ... }) in future.

local M = {}

-- Default developer-friendly values. These are safe defaults for most systems.
-- server_cmd defaults to "npm" so that "npm run dev:server" is used.
M.defaults = {
  server_cmd = "npm",
  server_args = { "run", "dev:server" },
  server_port = 43219,
  -- send_diffs controls whether the client attempts to compute and send diffs
  -- instead of full files. Currently the server accepts full markdown; diffs are a future improvement.
  send_diffs = false,
  -- developer-only flags can live here
  dev_local = true,
}

return M

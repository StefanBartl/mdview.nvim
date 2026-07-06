---@module 'plugin.mdview'
--- Plugin entrypoint for mdview.nvim.
---
--- The relay server and client bundle are prebuilt native assets fetched
--- from GitHub Releases on first use (see mdview.adapter.install) — there is
--- no runtime/toolchain requirement to gate plugin load on anymore. User
--- commands are registered by require('mdview').setup(), called from your
--- plugin manager's config function; this file only guards against double
--- loading.

if vim.g.loaded_mdview then
	return
end
vim.g.loaded_mdview = true

---@module 'mdview.config'
--- Top-level configuration for mdview.nvim, assembled from
--- config/DEFAULTS.lua. Users override via require('mdview').setup({...}).
---
--- M.merge mutates M.defaults (and its nested sub-tables) in place rather
--- than replacing it, so mdview.config.browser / mdview.config.usrcmd_start
--- — which point their own `M.defaults` at `M.defaults.browser` /
--- `M.defaults.start` — keep seeing live values regardless of whether they
--- were required before or after setup() runs.

local DEFAULTS = require("mdview.config.DEFAULTS")

local M = {}

---@type mdview.config.Defaults
M.defaults = vim.deepcopy(DEFAULTS)

---@param target table
---@param override table
local function deep_merge_in_place(target, override)
	for k, v in pairs(override) do
		if type(v) == "table" and type(target[k]) == "table" then
			deep_merge_in_place(target[k], v)
		else
			target[k] = v
		end
	end
end

--- Merge user-provided options into M.defaults in place (nested tables like
--- `browser`/`start` merge recursively, so a partial override such as
--- `{ browser = { browser = "firefox" } }` doesn't wipe out the rest of that
--- sub-table's defaults).
---@param opts table|nil
---@return mdview.config.Defaults
function M.merge(opts)
	if opts and not vim.tbl_isempty(opts) then
		deep_merge_in_place(M.defaults, opts)
	end
	return M.defaults
end

return M

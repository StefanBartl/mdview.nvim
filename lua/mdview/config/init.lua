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

-- Keys that legitimately default to nil, so they're absent from the DEFAULTS
-- table and can't be discovered by iterating it. Keyed by dotted table path.
local KNOWN_NIL_KEYS = {
	[""] = { server_cwd = true, file_log_path = true },
	browser = { open_url = true, resolved_browser_cmd = true, browser_args = true },
	start = { try_push_opts = true, wait_timeout_ms = true },
}

-- Collect every valid leaf key name across all levels (for "did you mean").
local function collect_known_names()
	local names = {}
	local function walk(tbl, path)
		for k, v in pairs(tbl) do
			if type(k) == "string" then
				names[k] = path == "" and k or (path .. "." .. k)
				if type(v) == "table" then
					walk(v, path == "" and k or (path .. "." .. k))
				end
			end
		end
	end
	walk(M.defaults, "")
	for path, keys in pairs(KNOWN_NIL_KEYS) do
		for k in pairs(keys) do
			names[k] = path == "" and k or (path .. "." .. k)
		end
	end
	return names
end

--- Warn about config keys the user passed that mdview doesn't recognize — the
--- usual cause is putting an `experimental.*` flag (line_diff / click_navigate /
--- reverse_scroll) at the top level, where it's silently ignored. Suggests the
--- correct path when the same key name exists elsewhere in the schema.
---@param opts table|nil
---@return nil
function M.validate(opts)
	if type(opts) ~= "table" then
		return
	end
	local known_names = collect_known_names()
	local unknown = {}

	local function check(user_tbl, default_tbl, path, nil_keys)
		for k, v in pairs(user_tbl) do
			local valid = (default_tbl[k] ~= nil) or (nil_keys and nil_keys[k])
			if not valid then
				local full = path == "" and tostring(k) or (path .. "." .. tostring(k))
				local suggestion = known_names[k]
				unknown[#unknown + 1] = suggestion and (("%s (did you mean `%s`?)"):format(full, suggestion))
					or full
			elseif type(v) == "table" and type(default_tbl[k]) == "table" then
				local sub = path == "" and tostring(k) or (path .. "." .. tostring(k))
				check(v, default_tbl[k], sub, KNOWN_NIL_KEYS[sub])
			end
		end
	end

	check(opts, M.defaults, "", KNOWN_NIL_KEYS[""])

	if #unknown > 0 then
		vim.notify(
			"[mdview] unknown setup() config key(s):\n  - " .. table.concat(unknown, "\n  - "),
			vim.log.levels.WARN
		)
	end
end

--- Merge user-provided options into M.defaults in place (nested tables like
--- `browser`/`start` merge recursively, so a partial override such as
--- `{ browser = { browser = "firefox" } }` doesn't wipe out the rest of that
--- sub-table's defaults).
---
--- Note: `{ key = nil }` cannot be used to reset `key` back to nil — Lua
--- never stores a nil-valued key in a table constructor, so `pairs(opts)`
--- never sees it. This matches `vim.tbl_deep_extend`'s own behavior, not a
--- bug specific to this function; call setup() with the field genuinely
--- omitted (not set to nil) if you don't want to override it.
---@param opts table|nil
---@return mdview.config.Defaults
function M.merge(opts)
	if opts and not vim.tbl_isempty(opts) then
		deep_merge_in_place(M.defaults, opts)
	end
	return M.defaults
end

return M

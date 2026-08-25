---@module 'scripts.minimal_init'
--- Minimal Neovim config that loads *only* mdview.nvim and its hard dependency
--- lib.nvim — nothing from the user's own configuration. Used as `nvim -u` by
--- the terminal wrappers (scripts/mdview-bg.*) to launch a standalone preview:
---
---   nvim --headless -u scripts/minimal_init.lua -c "MDView standalone file.md" -c "qa!"
---
--- This Neovim is only a launcher — `:MDView standalone` spawns the relay
--- detached (it watches the file on disk itself and outlives everything), then
--- this instance quits. Nothing long-lived runs here, so there's no headless
--- event-loop to keep warm.
---
--- Env vars honored (all optional, set by the callers):
---   $MDVIEW_PATH            mdview.nvim root (default: derived from this file)
---   $LIB_NVIM_PATH          lib.nvim root (same lookup order as TESTS/nvim/harness.lua)
---   $MDVIEW_STANDALONE_BIN  relay binary for standalone mode (needs --watch,
---                           v0.3.0+); until a release ships, point this at a
---                           locally built native/server/mdview-server

-- Nothing inherited: no user rtp, no shada, no swapfile. `-u <this file>`
-- already skips init.lua, but rtp still carries the site dirs.
vim.opt.shadafile = "NONE"
vim.opt.swapfile = false

---@return string # absolute path to the mdview.nvim repo root
local function mdview_root()
	if vim.env.MDVIEW_PATH and vim.env.MDVIEW_PATH ~= "" then
		return vim.fs.normalize(vim.env.MDVIEW_PATH)
	end
	-- This file lives at <root>/scripts/minimal_init.lua.
	local this = debug.getinfo(1, "S").source:sub(2)
	return vim.fs.normalize(vim.fn.fnamemodify(this, ":p:h:h"))
end

--- Locate lib.nvim. Same candidate order as TESTS/nvim/harness.lua, plus the
--- sibling-of-mdview case that matters when mdview itself was found via
--- $MDVIEW_PATH rather than the cwd.
---@param root string # mdview.nvim root
---@return string|nil
local function find_lib_nvim(root)
	-- Built by appending, not as a literal: an unset $LIB_NVIM_PATH would be a
	-- nil first element, and ipairs stops at the first nil — silently skipping
	-- every remaining candidate.
	local candidates = {}
	if vim.env.LIB_NVIM_PATH and vim.env.LIB_NVIM_PATH ~= "" then
		candidates[#candidates + 1] = vim.env.LIB_NVIM_PATH
	end
	candidates[#candidates + 1] = root .. "/../lib.nvim"
	candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"
	candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/site/pack/deps/start/lib.nvim"

	for _, path in ipairs(candidates) do
		local norm = vim.fs.normalize(path)
		if vim.fn.isdirectory(norm .. "/lua/lib") == 1 then
			return norm
		end
	end
	return nil
end

---@param path string
local function prepend_rtp(path)
	vim.opt.rtp:prepend(path)
	package.path = table.concat({
		path .. "/lua/?.lua",
		path .. "/lua/?/init.lua",
		package.path,
	}, ";")
end

local root = mdview_root()
if vim.fn.isdirectory(root .. "/lua/mdview") ~= 1 then
	io.stderr:write("[mdview] minimal_init: not an mdview.nvim checkout: " .. root .. "\n")
	vim.cmd("cq")
	return
end

local lib = find_lib_nvim(root)
if not lib then
	io.stderr:write("[mdview] minimal_init: cannot locate lib.nvim (hard dependency).\n")
	io.stderr:write("         Set $LIB_NVIM_PATH, or check it out next to mdview.nvim.\n")
	vim.cmd("cq")
	return
end

prepend_rtp(lib)
prepend_rtp(root)

-- Optional binary override lets a terminal launch use a locally built relay
-- (with --watch) before a v0.3.0 release exists — the same escape hatch as the
-- standalone.binary_path config key, surfaced as an env var for the wrappers.
local overrides = {}
if vim.env.MDVIEW_STANDALONE_BIN and vim.env.MDVIEW_STANDALONE_BIN ~= "" then
	overrides.standalone = { binary_path = vim.env.MDVIEW_STANDALONE_BIN }
end

require("mdview").setup(overrides)

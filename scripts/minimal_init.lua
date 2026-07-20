---@module 'scripts.minimal_init'
--- Minimal Neovim config that loads *only* mdview.nvim and its hard dependency
--- lib.nvim — nothing from the user's own configuration. Used as `nvim -u` for
--- detached background previews (`:MDView detach`, `scripts/mdview-bg.*`), so a
--- background preview can't be broken by an unrelated plugin in the user's
--- config, and can't drag that whole config into a long-lived process.
---
---   nvim --headless -u scripts/minimal_init.lua -c "MDView start" file.md
---
--- Env vars honored (all optional, set by the callers):
---   $MDVIEW_PATH        mdview.nvim root (default: derived from this file)
---   $LIB_NVIM_PATH      lib.nvim root (same lookup order as tests/nvim/harness.lua)
---   $MDVIEW_NO_BROWSER  "1" -> start the relay but don't open a browser tab

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

--- Locate lib.nvim. Same candidate order as tests/nvim/harness.lua, plus the
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

-- A detached background instance has no terminal to report into, so file
-- logging is on by default here — it's the only way to diagnose one after the
-- fact. Everything else stays at plugin defaults.
require("mdview").setup({
	file_log = true,
	browser = {
		browser_autostart = vim.env.MDVIEW_NO_BROWSER ~= "1",
		-- The instance outlives the terminal that spawned it; closing the tab
		-- should end it rather than leave an invisible nvim running forever.
		stop_on_browser_exit = true,
	},
})

-- Headless has no UI to keep the loop alive on its own once `-c` commands are
-- done, so quitting must be driven by the session ending. mdview's own
-- VimLeavePre autocmd still tears the relay down on :qa.
vim.api.nvim_create_autocmd("User", {
	pattern = "MDViewSessionEnded",
	callback = function()
		vim.cmd("qa!")
	end,
})

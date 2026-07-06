---@module 'mdview.health'
-- :checkhealth support for mdview.nvim.
--
-- The relay server and client bundle are native, prebuilt assets downloaded
-- once from GitHub Releases (see mdview.adapter.install) — there is no
-- Node/Go/Rust toolchain requirement for end users anymore. This check only
-- verifies the tools install.lua needs to fetch and verify those assets
-- (curl, tar), and reports whether they're already cached, without
-- triggering a download itself.

local M = {}

-- vim.health.start/ok/warn/error replaced the report_* names in Neovim 0.10;
-- fall back to the older names so :checkhealth still works on 0.9.
local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error_ = health.error or health.report_error

---@param cmd string
---@return boolean
local function executable(cmd)
	return vim.fn.executable(cmd) == 1
end

function M.check()
	start("mdview.nvim: environment")

	if vim.fn.has("nvim-0.9") == 1 then
		ok("Neovim >= 0.9")
	else
		error_("Neovim >= 0.9 is required")
	end

	if executable("curl") then
		ok("curl found (used to download the mdview-server release on first use)")
	else
		error_("curl not found in PATH — mdview.nvim cannot download the relay server binary or client bundle")
	end

	if executable("tar") then
		ok("tar found (used to extract the client bundle)")
	else
		error_("tar not found in PATH — mdview.nvim cannot extract the downloaded client bundle")
	end

	start("mdview.nvim: installed assets")

	local install = require("mdview.adapter.install")
	local status = install.status()

	if status.binary_installed then
		ok("mdview-server binary cached at " .. status.binary_path)
	else
		warn("mdview-server binary not yet installed — will be downloaded on first `:MDViewStart`")
	end

	if status.client_installed then
		ok("client bundle cached at " .. status.client_dir)
	else
		warn("client bundle not yet installed — will be downloaded on first `:MDViewStart`")
	end
end

return M

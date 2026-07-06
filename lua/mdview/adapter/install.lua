---@module 'mdview.adapter.install'
-- Ensures the platform-matching mdview-server binary and the prebuilt
-- browser client bundle (HTML/JS/WASM) are present locally, downloading and
-- checksum-verifying both from GitHub Releases on first use for this
-- version — same bootstrap pattern as mason.nvim/nvim-treesitter. No Go or
-- Rust toolchain is required on the end user's machine.

local fn = vim.fn
local log = require("mdview.helper.log")
local is_windows = require("mdview.helper.is_windows")

local M = {}

local CLIENT_ASSET = "mdview-client.tar.gz"

-- Read through to mdview.config.defaults.install so a fork or a pinned
-- release version (require('mdview').setup({ install = {...} })) is honored.
---@return string repo, string version
local function repo_and_version()
	local install_cfg = require("mdview.config").defaults.install
	return install_cfg.repo, install_cfg.version
end

---@return string os_name, string arch
local function platform_triplet()
	local os_name
	if is_windows() then
		os_name = "windows"
	elseif fn.has("mac") == 1 then
		os_name = "darwin"
	else
		os_name = "linux"
	end

	local arch = "amd64"
	local uv = vim.uv or vim.loop
	local uname = uv and uv.os_uname and uv.os_uname()
	if uname and uname.machine then
		local m = uname.machine:lower()
		if m:match("arm64") or m:match("aarch64") then
			arch = "arm64"
		end
	end

	return os_name, arch
end

---@return string
local function binary_name()
	local os_name, arch = platform_triplet()
	local ext = is_windows() and ".exe" or ""
	return string.format("mdview-server_%s_%s%s", os_name, arch, ext)
end

---@return string
local function install_dir()
	local _, version = repo_and_version()
	return fn.stdpath("data") .. "/mdview/bin/" .. version
end

-- Compute sha256 of a file's raw bytes.
---@param path string
---@return string|nil
local function file_sha256(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	if not content then
		return nil
	end
	return fn.sha256(content)
end

-- Parse a goreleaser-style checksums.txt (lines: "<sha256>  <filename>") and
-- return the expected checksum for `name`, or nil if not listed.
---@param checksums_text string
---@param name string
---@return string|nil
local function expected_checksum(checksums_text, name)
	for line in checksums_text:gmatch("[^\r\n]+") do
		local sum, fname = line:match("^(%x+)%s+%*?(.+)$")
		if sum and fname == name then
			return sum:lower()
		end
	end
	return nil
end

---@param url string
---@param dest string
---@return boolean ok, string|nil err
local function curl_download(url, dest)
	if fn.executable("curl") ~= 1 then
		return false, "curl not found in PATH; cannot download mdview release assets"
	end
	fn.system({ "curl", "-fsSL", "-o", dest, url })
	if vim.v.shell_error ~= 0 then
		return false, ("curl failed (exit %d) for %s"):format(vim.v.shell_error, url)
	end
	return true, nil
end

-- Download `name` from the configured release into dir/name (skipped if it
-- already exists) and verify it against dir/checksums.txt.
---@param dir string
---@param name string
---@return string|nil path, string|nil err
local function ensure_asset(dir, name)
	local path = dir .. "/" .. name
	if fn.filereadable(path) == 1 then
		return path, nil
	end

	local mkdir_ok = pcall(fn.mkdir, dir, "p")
	if not mkdir_ok then
		return nil, "failed to create install directory: " .. dir
	end

	local repo, version = repo_and_version()
	local base_url = ("https://github.com/%s/releases/download/%s"):format(repo, version)
	local checksums_path = dir .. "/checksums.txt"
	if fn.filereadable(checksums_path) == 0 then
		local ok, err = curl_download(base_url .. "/checksums.txt", checksums_path)
		if not ok then
			return nil, err
		end
	end

	local dl_ok, dl_err = curl_download(base_url .. "/" .. name, path)
	if not dl_ok then
		return nil, dl_err
	end

	local cf = io.open(checksums_path, "r")
	if not cf then
		return nil, "failed to read downloaded checksums.txt"
	end
	local checksums_text = cf:read("*a")
	cf:close()

	local expected = expected_checksum(checksums_text, name)
	if not expected then
		pcall(os.remove, path)
		return nil, "no checksum entry found for " .. name .. " in checksums.txt"
	end

	local actual = file_sha256(path)
	if not actual or actual:lower() ~= expected then
		pcall(os.remove, path)
		return nil, ("checksum mismatch for %s: expected %s, got %s"):format(name, expected, tostring(actual))
	end

	log.debug("verified and installed " .. name, nil, "install", true)
	return path, nil
end

-- Report whether the platform binary / client bundle for the currently
-- configured install version are already installed, without downloading or
-- verifying anything. Read-only — safe to call from :checkhealth.
---@return { binary_installed: boolean, binary_path: string, client_installed: boolean, client_dir: string }
function M.status()
	local dir = install_dir()
	local bin_path = dir .. "/" .. binary_name()
	local client_dir = dir .. "/client"
	return {
		binary_installed = fn.filereadable(bin_path) == 1,
		binary_path = bin_path,
		client_installed = fn.isdirectory(client_dir) == 1,
		client_dir = client_dir,
	}
end

-- Ensure the platform-matching mdview-server binary is present and
-- checksum-verified. Returns its absolute path.
---@return string|nil path, string|nil err
function M.ensure_binary()
	local dir = install_dir()
	local name = binary_name()

	local path, err = ensure_asset(dir, name)
	if not path then
		return nil, err
	end

	if not is_windows() then
		fn.system({ "chmod", "+x", path })
	end

	return path, nil
end

-- Ensure the prebuilt browser client bundle (HTML/JS/WASM) is present,
-- checksum-verified, and extracted. Returns the directory to pass to the
-- server as --web-root.
---@return string|nil web_root, string|nil err
function M.ensure_client_bundle()
	local dir = install_dir()
	local extracted_dir = dir .. "/client"

	if fn.isdirectory(extracted_dir) == 1 then
		return extracted_dir, nil
	end

	local archive_path, err = ensure_asset(dir, CLIENT_ASSET)
	if not archive_path then
		return nil, err
	end

	local mkdir_ok = pcall(fn.mkdir, extracted_dir, "p")
	if not mkdir_ok then
		return nil, "failed to create client bundle directory: " .. extracted_dir
	end

	fn.system({ "tar", "-xzf", archive_path, "-C", extracted_dir })
	if vim.v.shell_error ~= 0 then
		return nil, "failed to extract " .. CLIENT_ASSET
	end

	return extracted_dir, nil
end

return M

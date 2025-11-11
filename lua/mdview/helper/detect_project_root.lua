---@module 'mdview.helper.detect_project_root'
-- project root detector used for reasonable default cwd

local path_join = require("mdview.helper.path_join")
local file_exists = require("mdview.helper.file_exists")

---@return string|nil  # returns the detected project root path or nil if none found
return function ()
	-- DEVONLY: Remove REPOS_DIR in production
	-- 1) REPOS_DIR if set and contains mdview repo
	local repos_dir = vim.env.REPOS_DIR
	if repos_dir and repos_dir ~= "" then
		local candidates = { path_join(repos_dir, "mdview.nvim"), path_join(repos_dir, "mdview") }
		for _, cand in ipairs(candidates) do
			if
				file_exists(path_join(cand, "package.json"))
				or file_exists(path_join(cand, "lua", "mdview", "health.lua"))
			then
				return cand
			end
		end
	end

	-- 2) git root
	local ok, handle = pcall(io.popen, "git rev-parse --show-toplevel 2>nul")
	if ok and handle then
		local out = handle:read("*a")
		pcall(handle.close, handle)
		out = out and out:gsub("%s+$", "") or ""
		if out ~= "" and file_exists(path_join(out, "package.json")) then
			return out
		end
	end

	-- 3) cwd if it contains package.json
	local cwd = vim.fn.getcwd()
	if file_exists(path_join(cwd, "package.json")) then
		return cwd
	end

	return nil
end

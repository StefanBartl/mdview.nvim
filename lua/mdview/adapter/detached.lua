---@module 'mdview.adapter.detached'
--- Spawns processes that must OUTLIVE this Neovim instance.
---
--- Deliberately separate from mdview.adapter.runner rather than a flag on it:
--- runner's relay child is bound to this instance on purpose (VimLeavePre kills
--- it, stdout is piped into the log buffer, state tracks the handle). A detached
--- process needs the exact opposite of all three — no parent link, no pipes to
--- keep open, no state entry to go stale once we exit. Mixing the two into one
--- function would mean every caller has to get three unrelated flags right.

---@diagnostic disable: undefined-field

local uv = vim.loop

local M = {}

--- Build the child's environment as libuv wants it (a list of "KEY=VALUE"),
--- inheriting this process's environment and layering `extra` on top.
---
--- Passing an explicit env rather than mutating `vim.env` around the spawn is
--- deliberate: `vim.env.X = nil` genuinely unsets a variable, so a
--- save-and-restore around the call cannot distinguish "was unset" from "was
--- absent from my restore table" and would leak the override into this
--- instance's own environment.
---@param extra table<string, string>|nil
---@return string[]|nil # nil when there is nothing to add (inherit as-is)
function M.build_env(extra)
	if not extra or vim.tbl_isempty(extra) then
		return nil
	end

	local merged = vim.fn.environ()
	for k, v in pairs(extra) do
		merged[k] = v
	end

	local out = {}
	for k, v in pairs(merged) do
		out[#out + 1] = ("%s=%s"):format(k, v)
	end
	return out
end

--- Spawn `cmd` with `args` fully detached: it survives `:qa` of this instance,
--- and its stdio is discarded rather than piped (nothing here will be alive to
--- read it, and an unread pipe eventually blocks the child's writes).
---@param cmd string # executable name or absolute path
---@param args string[] # argument vector
---@param cwd string|nil # working directory for the child
---@param extra_env table<string, string>|nil # vars added on top of the inherited environment
---@return integer|nil pid, string|nil err
function M.spawn(cmd, args, cwd, extra_env)
	if type(cmd) ~= "string" or cmd == "" then
		return nil, "invalid command: " .. tostring(cmd)
	end

	local handle, pid = uv.spawn(cmd, {
		args = args or {},
		cwd = cwd,
		env = M.build_env(extra_env),
		-- detached: the child gets its own process group, so it is not killed
		-- with us and is not attached to our terminal's signals.
		detached = true,
		-- No pipes: the child's output goes nowhere. Background instances log
		-- to a file instead (minimal_init.lua turns file_log on for exactly
		-- this reason), which is readable after the fact.
		stdio = { nil, nil, nil },
	}, function() end)

	if not handle then
		-- uv.spawn returns (nil, "ENOENT: ...") — the second value is the error.
		return nil, tostring(pid)
	end

	-- unref, then close: unref drops the handle from the event loop's refcount
	-- so it can't keep this instance alive at exit, and closing it releases our
	-- side without signalling the (already independent) child.
	pcall(function()
		handle:unref()
		handle:close()
	end)

	return pid, nil
end

--- Absolute path to this mdview.nvim checkout, derived from this file's own
--- location (<root>/lua/mdview/adapter/detached.lua). Used to point a detached
--- Neovim at scripts/minimal_init.lua — asking the runtimepath instead would
--- find whichever copy the *user's* config loaded, which in a multi-checkout
--- setup is not necessarily the one running this code.
---@return string
function M.plugin_root()
	local this = debug.getinfo(1, "S").source:sub(2)
	return vim.fs.normalize(vim.fn.fnamemodify(this, ":p:h:h:h:h"))
end

--- Resolve the file a detached preview should target: the explicit argument if
--- given, else the current buffer's file. Returns nil for an unnamed buffer,
--- since a background process has no buffer to read and needs a real path.
---@param arg string|nil
---@return string|nil path, string|nil err
function M.resolve_target(arg)
	local path
	if arg and arg ~= "" then
		path = vim.fn.fnamemodify(vim.fn.expand(arg), ":p")
	else
		path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
		if path == "" then
			return nil, "current buffer has no file — pass a path, e.g. :MDView detach README.md"
		end
		path = vim.fn.fnamemodify(path, ":p")
	end

	if vim.fn.filereadable(path) ~= 1 then
		return nil, "not a readable file: " .. path
	end
	return vim.fs.normalize(path), nil
end

return M

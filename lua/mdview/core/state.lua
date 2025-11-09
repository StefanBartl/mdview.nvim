---@module 'mdview.core.state'
-- Small, safe state container for 'web' related runtime handles and flags.
-- Provides explicit getter/setter functions and simple validation so other
-- modules do not mutate the internal table directly.

local vim = vim
local M = {}

-- AUDIT: Neben vime_leave und bufenter auch andere autcmds id nach state?
M._autocmd_ids = {}

---@type mdview.core.state.web
local web_state = {
	attached = false,
	browser = nil,
	server = nil,
}

-- AUDIT: Momentan nicht verwendet
---@type mdview.core.state.runner
M.runner = {
	proc = nil,
	server_job = nil,
}

-- Helper ------------------------------------------------------------

-- EmmyLua enum
---@enum mdview.core.state.WebKey
local WebKey = {
	attached = "attached",
	browser = "browser",
	server = "server",
}

-- expose the enum/table for callers who prefer constants instead of raw strings
M.WebKey = WebKey

-- shallow copy a table (used for defensive getters)
---@param t table
---@return table
local function shallow_copy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

-- validate a key is one of the allowed enum members
---@param k string
---@return boolean
local function is_valid_key(k)
	return k == WebKey.attached or k == WebKey.browser or k == WebKey.server
end

-- Web API  ----------------

--- Return the value for a specific web key.
--- This function accepts a typed key (enum) so LSP can offer completions.
--- @param key mdview.core.state.WebKey
--- @return any
function M.get_entry(key)
	if not is_valid_key(key) then
		error("get_entry: invalid key (expected one of 'attached','browser','server')", 2)
	end
	-- return the raw value (not a copy) for handles, and a primitive for booleans
	return web_state[key]
end

--- Set a specific web key to a new value and return the previous value.
--- Accepts the same enum keys as get_entry. Validation is applied for 'attached'
--- to ensure boolean semantics.
--- @param key mdview.core.state.WebKey
--- @param val any
--- @return any previous_value
function M.set_web_entry(key, val)
	if not is_valid_key(key) then
		error("set_entry: invalid key (expected one of 'attached','browser','server')", 2)
	end

	-- Validate 'attached' must be boolean
	if key == WebKey.attached and type(val) ~= "boolean" then
		error("set_entry: 'attached' must be boolean", 2)
	end

	local prev = web_state[key]
	web_state[key] = val
	return prev
end

--- Clear (set to nil) the given web entry and return previous value.
--- @param key mdview.core.state.WebKey
--- @return any previous_value
function M.clear_web_entry(key)
	if not is_valid_key(key) then
		error("clear_entry: invalid key (expected one of 'attached','browser','server')", 2)
	end
	local prev = web_state[key]
	web_state[key] = nil
	return prev
end

-- Return a defensive copy of the web state.
-- Return a shallow copy to discourage direct mutation by callers.
--- @return mdview.core.state.web
function M.get_web()
	return shallow_copy(web_state)
end

-- Replace the entire web state with the provided table (validated).
-- Partial tables are allowed; missing keys keep their current values.
--- @param t table
--- @return mdview.core.state.web current state after merge
function M.set_web(t)
	if type(t) ~= "table" then
		error("set_web expects a table", 2)
	end
	if t.attached ~= nil then
		if type(t.attached) ~= "boolean" then
			error("web.attached must be boolean", 2)
		end
		web_state.attached = t.attached
	end
	if t.browser ~= nil then
		web_state.browser = t.browser
	end
	if t.server ~= nil then
		web_state.server = t.server
	end
	return shallow_copy(web_state)
end

-- Atomically update the web state using a callback.
-- The callback receives a shallow copy of the current state and may return a
--  table with keys to change (attached/browser/server). Any returned non-table
--  value is ignored.
--- @param fn fun(cur_state: mdview.core.state.web): table|nil
--- @return mdview.core.state.web current state after update
function M.update_web(fn)
	if type(fn) ~= "function" then
		error("update_web expects a function", 2)
	end
	local snapshot = shallow_copy(web_state)
	local ok, res = pcall(fn, snapshot)
	if not ok then
		vim.notify("update_web callback failed: " .. tostring(res), vim.log.levels.ERROR)
		return shallow_copy(web_state)
	end
	if type(res) == "table" then
		return M.set_web(res)
	end
	return shallow_copy(web_state)
end

--- @return boolean
function M.is_attached()
	return web_state.attached == true
end

-- Set attached flag. Returns previous value.
--- @param val boolean
--- @return boolean previous
function M.set_attached(val)
	if type(val) ~= "boolean" then
		error("set_attached expects boolean", 2)
	end
	local prev = web_state.attached
	web_state.attached = val
	return prev
end

-- Get current browser handle (may be nil).
--- @return any
function M.get_browser()
	return web_state.browser
end

-- Set browser handle: Returns previous handle.
--- @param handle any
--- @return any previous
function M.set_browser(handle)
	local prev = web_state.browser
	web_state.browser = handle
	return prev
end

-- Clear browser handle (set to nil). Returns previous handle.
--- @return any previous
function M.clear_browser()
	local prev = web_state.browser
	web_state.browser = nil
	return prev
end

-- Get current server/runner handle (may be nil).
--- @return any
function M.get_server()
	return web_state.server
end

-- Set server handle (opaque). Returns previous handle.
--- @param handle any
--- @return any previous
function M.set_server(handle)
	local prev = web_state.server
	web_state.server = handle
	return prev
end

-- Clear server handle (set to nil). Returns previous handle.
--- @return any previous
function M.clear_server()
	local prev = web_state.server
	web_state.server = nil
	return prev
end

-- Reset web_state to initial values and return previous snapshot.
--- @return mdview.core.state.web previous_state
function M.reset_web()
	local prev = shallow_copy(web_state)
	web_state.attached = false
	web_state.browser = nil
	web_state.server = nil
	return prev
end

-- Runner API  ----------------

--- Get the current proc handle (may be nil).
--- @return any|nil
function M.get_proc()
	return M.runner.proc
end
--- Set the proc handle; returns previous handle.
--- @param h any
--- @return any previous
function M.set_proc(h)
	local prev = M.runner.proc
	M.runner.proc = h
	return prev
end

--- Clear the proc handle and return previous value.
--- @return any previous
function M.clear_proc()
	local prev = M.runner.proc
	M.runner.proc = nil
	return prev
end

--- Get the current server_job handle/metadata (may be nil).
--- @return any|nil
function M.get_server_job()
	return M.runner.server_job
end

--- Set the server_job handle/metadata; returns previous value.
--- @param j any
--- @return any previous
function M.set_server_job(j)
	local prev = M.runner.server_job
	M.runner.server_job = j
	return prev
end

--- Clear the server_job entry and return previous value.
--- @return any previous
function M.clear_server_job()
	local prev = M.runner.server_job
	M.runner.server_job = nil
	return prev
end

return M

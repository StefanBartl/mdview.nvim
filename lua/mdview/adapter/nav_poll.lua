---@module 'mdview.adapter.nav_poll'
-- Browser->Neovim half of click-to-navigate (experimental.click_navigate).
-- While a session is active, polls the relay's GET /nav for links the user
-- clicked in the preview, resolves each against the source document's
-- directory, and opens the target in Neovim (`:edit`). Opening the file makes
-- it the active buffer, so the existing browser.behavior machinery
-- (bindings/autocmds/buffer_switch) pushes it into the preview — no extra
-- rendering path here.
--
-- Deliberately a poll rather than a persistent socket: Neovim has no WebSocket
-- client, the relay stays a dumb byte-forwarder, and a click is a rare,
-- latency-tolerant action. curl is already a hard dependency.

local uv = vim.uv or vim.loop

local M = {}

local INTERVAL_MS = 500
local timer = nil
local inflight = false

---@return string
local function nav_url()
	local port = vim.g.mdview_server_port or 43219
	local token = require("mdview.core.state").get_token() or ""
	return string.format("http://localhost:%d/nav?token=%s", port, vim.uri_encode(token))
end

-- Resolve `href` (relative to `key`'s directory) and open it in Neovim.
---@param key string # source document path (the room the click happened in)
---@param href string # clicked relative href
local function handle_nav(key, href)
	if type(key) ~= "string" or type(href) ~= "string" or href == "" then
		return
	end
	local dir = vim.fn.fnamemodify(key, ":h")
	local target = vim.fn.simplify(dir .. "/" .. href)
	local norm = require("mdview.helper.normalize").path(target)
	if norm then
		target = norm
	end
	if vim.fn.filereadable(target) ~= 1 then
		vim.notify("[mdview] click-navigate: file not found: " .. target, vim.log.levels.WARN)
		return
	end
	-- Opening the file triggers buffer_switch, which pushes it to the preview
	-- per browser.behavior. pcall so a bad path can never break the poll loop.
	pcall(vim.cmd.edit, vim.fn.fnameescape(target))
end

local function poll_once()
	if inflight then
		return
	end
	if not require("mdview.core.state").get_server() then
		return
	end
	if vim.fn.executable("curl") ~= 1 then
		return
	end
	inflight = true
	vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", nav_url() }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data then
				return
			end
			local body = vim.trim(table.concat(data, "\n"))
			if body == "" or body == "null" then
				return
			end
			local ok, arr = pcall(vim.json.decode, body)
			if not ok or type(arr) ~= "table" then
				return
			end
			vim.schedule(function()
				for _, r in ipairs(arr) do
					if type(r) == "table" then
						handle_nav(r.key, r.href)
					end
				end
			end)
		end,
		on_exit = function()
			inflight = false
		end,
	})
end

--- Start polling for navigation events. No-op unless experimental.click_navigate
--- is enabled and curl is available. Safe to call repeatedly.
---@return nil
function M.start()
	if timer then
		return
	end
	local exp = require("mdview.config").defaults.experimental
	if not (exp and exp.click_navigate == true) then
		return
	end
	timer = uv.new_timer()
	timer:start(INTERVAL_MS, INTERVAL_MS, vim.schedule_wrap(poll_once))
end

--- Stop polling. Safe to call when not started.
---@return nil
function M.stop()
	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
		timer = nil
	end
	inflight = false
end

return M

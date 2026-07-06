---@module 'mdview.bindings.autocmds.live_push'
-- Setup live markdown push on insert/change events and on save.
-- Always sends the full current buffer content via mdview.adapter.ws_client;
-- the client WASM renderer needs whole-document context to render correctly,
-- so partial-line diff pushing is not compatible with the current
-- architecture (line-diff transport may be reintroduced later as a
-- bandwidth optimization once the client can reconstruct full text from
-- diffs — see doc/Roadmap/Roadmap.md).
-- Adds debug logging controlled via mdview.config.defaults.debug_preview

local api = vim.api
local ws_client = require("mdview.adapter.ws_client")
local session = require("mdview.core.session")
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")
local log = require("mdview.helper.log")
local normalize = require("mdview.helper.normalize")
local defaults = require("mdview.config").defaults
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

M._attached_groups = M._attached_groups or {}

-- Send the full current content of bufnr to the relay server (immediate,
-- unqueued POST) and store a session snapshot for bookkeeping.
---@param bufnr integer
function M.push_buffer_changes(bufnr)
	local ft = safe_buf_get_option(bufnr, "filetype") or ""
	if ft ~= "markdown" and ft ~= "md" then
		log.debug("skipping buffer, filetype: " .. ft, nil, "livepush", true)
		return
	end

	local path = api.nvim_buf_get_name(bufnr)
	if path == "" then
		log.debug("skipping buffer, empty path", nil, "livepush", true)
		return
	end

	local norm_path = normalize.path(path)
	if norm_path then
		path = norm_path
	else
		log.debug("normalized path ist nil", vim.log.levels.ERROR, "live_push", true)
		return
	end

	local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
	local payload = table.concat(lines, "\n")

	ws_client.send_markdown(path, payload, { immediate = true })
	session.store(path, lines)
	log.debug("full push sent and session stored for " .. path, nil, "livepush", true)
end

--- Setup autocmds for live push and save
--- @param group integer|nil
function M.attach(group)
	group = group or 0
	if M._attached_groups[group] then
		return
	end
	M._attached_groups[group] = true
	log.debug("setting up live push autocmds", nil, "livepush", true)

	local opts_a = {
		group = group,
		pattern = defaults.ft_pattern,
		callback = function(args)
			ws_client.wait_ready(function()
				log.debug("TextChanged fired, buf: " .. args.buf, nil, "livepush", true)
				M.push_buffer_changes(args.buf)
			end, ws_client.WAIT_READY_TIMEOUT)
		end,
	}
	local id_a = api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, opts_a)
	autocmd_registry.register(group, id_a)

	local opts_b = {
		group = group,
		pattern = defaults.ft_pattern,
		callback = function(args)
			ws_client.wait_ready(function()
				log.debug("BufWritePost fired, full push, buf: " .. args.buf, nil, "livepush", true)
				M.push_buffer_changes(args.buf)
			end, ws_client.WAIT_READY_TIMEOUT)
		end,
	}
	local id_b = api.nvim_create_autocmd("BufWritePost", opts_b)
	autocmd_registry.register(group, id_b)
end

return M

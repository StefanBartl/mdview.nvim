---@module 'mdview.autocmds.live_push'
-- Setup live markdown push on insert/change events **and** on save.
-- Uses mdview.adapter.ws_client.send_markdown to send updates per buffer change.
-- Combines granular diffs for typing and full push on write (`:w`) for reliability.
-- Adds debug logging controlled via mdview.config.defaults.debug_preview

-- AUDIT: Annotations

local api = vim.api
local ws_client = require("mdview.adapter.ws_client")
local session = require("mdview.core.session")
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")
local diff = require("mdview.utils.diff_granular")
local log = require("mdview.helper.log")
local normalize = require("mdview.helper.normalize")

local M = {}

-- Small tweak to push_buffer_changes:
--  * skip if diffs == {} (no-op)
--  * on full_push use immediate POST and store snapshot afterwards
--  * for diffs: avoid sending empty payloads
---@param bufnr integer
---@param full_push boolean|nil
function M.push_buffer_changes(bufnr, full_push)
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
	local prev = session.get(path)
	local old_lines = (prev and prev.lines) or {}
	local new_lines = lines

	for i = 1, #old_lines do
		if old_lines[i] == nil then
			old_lines[i] = ""
		end
	end
	for i = 1, #new_lines do
		if new_lines[i] == nil then
			new_lines[i] = ""
		end
	end

	local diffs = full_push and { { op = "replace", start = 0, count = #new_lines } } or diff(old_lines, new_lines)
	log.debug("diffs calculated: " .. vim.inspect(diffs), nil, "livepush", true)

	-- nothing to do
	if not diffs or #diffs == 0 then
		log.debug("no diffs to send for " .. path, nil, "livepush", true)
		return
	end

	-- full push: immediate POST and store snapshot after call
	if full_push then
		local payload = table.concat(new_lines, "\n")
		-- immediate option bypasses queue and posts right away
		ws_client.send_markdown(path, payload, { immediate = true })
		-- store snapshot immediately after forced send (best-effort)
		session.store(path, new_lines)
		log.debug("full_push immediate sent and session stored for " .. path, nil, "livepush", true)
		return
	end

	-- send diff chunks (coalesced / queued)
	for _, d in ipairs(diffs) do
		local chunk_lines = {}
		if d.op == "replace" or d.op == "insert" then
			chunk_lines = vim.list_slice(new_lines, d.start + 1, d.start + (d.count or #new_lines))
		end
		-- skip empty chunk (delete handled as empty payload intentionally)
		if #chunk_lines == 0 and d.op ~= "delete" then
			log.debug("skipping empty chunk", nil, "livepush", true)
		else
			local payload = table.concat(chunk_lines, "\n")
			log.debug(
				string.format("sending patch for path=%s op=%s lines=%d", path, d.op, #chunk_lines),
				nil,
				"livepush",
				true
			)
			ws_client.send_markdown(path, payload)
		end
	end

	-- update session after enqueuing diffs (keeps canonical snapshot for next diff computation)
	session.store(path, new_lines)
	log.debug("buffer state stored for path: " .. path, nil, "livepush", true)
end

--- Setup autocmds for live push and save
function M.setup()
	log.debug("setting up live push autocmds", nil, "livepush", true)

	api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		pattern = "*.md",
		callback = function(args)
			ws_client.wait_ready(function()
				log.debug("TextChanged fired, buf: " .. args.buf, nil, "livepush", true)
				M.push_buffer_changes(args.buf, false)
			end, ws_client.WAIT_READY_TIMEOUT)
		end,
	})

	api.nvim_create_autocmd("BufWritePost", {
		pattern = "*.md",
		callback = function(args)
			ws_client.wait_ready(function()
				log.debug("BufWritePost fired, full push, buf: " .. args.buf, nil, "livepush", true)
				M.push_buffer_changes(args.buf, true)
			end, ws_client.WAIT_READY_TIMEOUT)
		end,
	})
end

return M

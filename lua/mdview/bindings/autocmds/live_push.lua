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

-- Send the current content of bufnr to the relay for `bufnr`'s room and store a
-- session snapshot for bookkeeping. Routing (per-path vs the preview key) and
-- full-vs-diff (when experimental.line_diff is on) are decided here / in
-- ws_client.send_content. Pass { full = true } to force a full snapshot (e.g.
-- on save or when seeding a freshly opened tab).
---@param bufnr integer
---@param opts { full?: boolean }|nil
function M.push_buffer_changes(bufnr, opts)
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

	-- In "reuse" browser_behavior the single preview tab follows the active
	-- buffer, so route this buffer's content to the room the open tab is
	-- watching (the preview key) rather than this buffer's own path. For
	-- "new_tab"/"manual" — and whenever no tab has been opened yet — push to
	-- the buffer's own path, i.e. the original per-document room model.
	local target = path
	local behavior = require("mdview.config.browser").defaults.behavior or "reuse"
	if behavior == "reuse" then
		local preview_key = require("mdview.core.state").get_preview_key()
		if type(preview_key) == "string" and preview_key ~= "" then
			target = preview_key
		end
	end

	ws_client.send_content(target, lines, { full = opts and opts.full == true or nil })
	session.store(path, lines)
	log.debug("content push sent (target=" .. target .. ") and session stored for " .. path, nil, "livepush", true)
end

--- Setup autocmds for live push and save. Called once per attach cycle from
--- mdview.bindings.autocmds.attach (whose own augroup_id guard prevents
--- double-attach); no separate dedup needed here.
--- @param group integer|nil # augroup id; nil registers without a group
--- (nvim_create_autocmd rejects group = 0, so nil must NOT be coerced to 0)
function M.attach(group)
	log.debug("setting up live push autocmds", nil, "livepush", true)

	local opts_a = {
		pattern = defaults.ft_pattern,
		callback = function(args)
			ws_client.wait_ready(function(ok)
				if not ok then
					return
				end
				log.debug("TextChanged fired, buf: " .. args.buf, nil, "livepush", true)
				M.push_buffer_changes(args.buf)
			end, ws_client.WAIT_READY_TIMEOUT)
		end,
	}
	if group then
		opts_a.group = group
	end
	local id_a = api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, opts_a)
	autocmd_registry.register(group, id_a)

	local opts_b = {
		pattern = defaults.ft_pattern,
		callback = function(args)
			ws_client.wait_ready(function(ok)
				if not ok then
					return
				end
				log.debug("BufWritePost fired, full push, buf: " .. args.buf, nil, "livepush", true)
				-- Force a full snapshot on save: cheap resync point that reseeds
				-- the relay's LastPayload and heals any diff desync.
				M.push_buffer_changes(args.buf, { full = true })
			end, ws_client.WAIT_READY_TIMEOUT)
		end,
	}
	if group then
		opts_b.group = group
	end
	local id_b = api.nvim_create_autocmd("BufWritePost", opts_b)
	autocmd_registry.register(group, id_b)
end

return M

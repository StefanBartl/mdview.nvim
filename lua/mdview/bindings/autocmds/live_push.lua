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
local target_key = require("mdview.helper.target_key")
local defaults = require("mdview.config").defaults
local autocmd_registry = require("mdview.helper.autocmds_registry")

local M = {}

-- Last document previewed per target room, so a doc-changed ping fires once per
-- new document (not per keystroke). Reset each attach cycle.
---@type table<string, string>
M._last_doc = {}

---@internal
---@return integer
local function now_ms()
	local uv = vim.uv or vim.loop
	return uv.now()
end

-- Throttle state for TextChanged/TextChangedI (see the CPU benchmark in
-- Roadmap.md's "Performance" section: unthrottled, every keystroke spawned its
-- own curl process). Unlike scroll_sync's throttle — which just drops a ping
-- that arrives too soon, fine for a transient scroll position — dropping a
-- content push would leave the preview stale indefinitely with nothing else to
-- trigger a resync. So a push inside the throttle window is deferred to a
-- single trailing timer instead of dropped, guaranteeing the latest content is
-- eventually sent no more than throttle_ms after it was made.
local last_sent_at = 0
local pending_timer = nil
local pending_bufnr = nil

---@internal
---@return nil
local function cancel_pending()
	if pending_timer then
		pending_timer:stop()
		pending_timer:close()
		pending_timer = nil
	end
end

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
	local target = target_key.resolve(bufnr) or path

	ws_client.send_content(target, lines, { full = opts and opts.full == true or nil })
	session.store(path, lines)

	-- Tell the tab which document it's now showing whenever it changes (initial
	-- push, or a buffer switch in "reuse" mode) — powers browser Back/Forward.
	-- Keyed by target room so it fires once per new document, not per keystroke.
	if M._last_doc[target] ~= path then
		M._last_doc[target] = path
		ws_client.send_doc(target, path)
	end

	log.debug("content push sent (target=" .. target .. ") and session stored for " .. path, nil, "livepush", true)
end

--- Setup autocmds for live push and save. Called once per attach cycle from
--- mdview.bindings.autocmds.attach (whose own augroup_id guard prevents
--- double-attach); no separate dedup needed here.
--- @param group integer|nil # augroup id; nil registers without a group
--- (nvim_create_autocmd rejects group = 0, so nil must NOT be coerced to 0)
function M.attach(group)
	log.debug("setting up live push autocmds", nil, "livepush", true)
	M._last_doc = {} -- fresh session: re-announce the document on the first push
	last_sent_at = 0
	cancel_pending()

	---@internal
	---@param bufnr integer
	---@return nil
	local function push_now(bufnr)
		ws_client.wait_ready(function(ok)
			if not ok then
				return
			end
			log.debug("TextChanged fired, buf: " .. bufnr, nil, "livepush", true)
			M.push_buffer_changes(bufnr)
		end, ws_client.WAIT_READY_TIMEOUT)
	end

	local opts_a = {
		pattern = defaults.ft_pattern,
		callback = function(args)
			local throttle_ms = defaults.live_push_throttle_ms or 150
			local t = now_ms()
			if t - last_sent_at >= throttle_ms then
				cancel_pending()
				last_sent_at = t
				push_now(args.buf)
				return
			end

			-- Within the throttle window: remember the latest buffer and make
			-- sure exactly one trailing push is scheduled for when the window
			-- ends (don't reschedule on every keystroke, or continuous typing
			-- would never actually fire one).
			pending_bufnr = args.buf
			if not pending_timer then
				local remaining = throttle_ms - (t - last_sent_at)
				pending_timer = (vim.uv or vim.loop).new_timer()
				pending_timer:start(
					math.max(0, remaining),
					0,
					vim.schedule_wrap(function()
						cancel_pending()
						last_sent_at = now_ms()
						push_now(pending_bufnr)
					end)
				)
			end
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

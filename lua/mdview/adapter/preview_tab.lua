---@module 'mdview.adapter.preview_tab'
-- Standalone "preview in an nvim tab instead of the browser" feature (see
-- docs/Roadmap/Roadmap.md's bonus features). Deliberately decoupled from the
-- browser/WASM rendering pipeline (native/wasm-render, native/server) —
-- there is no HTML rendering here at all, no relay server, no WebSocket, no
-- external tool dependency (no `glow`/`mdcat` subprocess). It mirrors the
-- source buffer's raw text into a read-only scratch buffer in its own tab,
-- highlighted via Neovim's markdown Treesitter parser (falling back to Vim's
-- bundled regex `syntax=markdown` if Treesitter's markdown parser isn't
-- installed, so it's never left unhighlighted). Works fully independently
-- of :MDViewStart / the relay session.

local api = vim.api
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")

local M = {}

---@type table<integer, integer> source bufnr -> preview bufnr
local source_to_preview = {}
---@type table<integer, integer> preview bufnr -> source bufnr
local preview_to_source = {}
---@type table<integer, integer> preview bufnr -> tabpage handle it was opened in
local preview_tabpage = {}

---@param source_bufnr integer
---@return boolean
local function is_markdown(source_bufnr)
	local ft = safe_buf_get_option(source_bufnr, "filetype") or ""
	return ft == "markdown" or ft == "md"
end

-- Apply Treesitter markdown highlighting if the parser is available, else
-- fall back to Vim's bundled regex syntax file (ships with Neovim, no
-- install needed) so the preview is never left completely unhighlighted.
---@param preview_bufnr integer
local function apply_highlighting(preview_bufnr)
	local ok = pcall(vim.treesitter.start, preview_bufnr, "markdown")
	if not ok then
		vim.bo[preview_bufnr].syntax = "markdown"
	end
end

-- Refill preview_bufnr's lines from source_bufnr, preserving the cursor
-- position of any window currently showing the preview so it doesn't jump
-- to the top on every keystroke in the source buffer.
---@param source_bufnr integer
---@param preview_bufnr integer
local function sync_content(source_bufnr, preview_bufnr)
	if not api.nvim_buf_is_valid(source_bufnr) or not api.nvim_buf_is_valid(preview_bufnr) then
		return
	end
	local lines = api.nvim_buf_get_lines(source_bufnr, 0, -1, false)

	local win_cursors = {}
	for _, winid in ipairs(vim.fn.win_findbuf(preview_bufnr)) do
		win_cursors[winid] = api.nvim_win_get_cursor(winid)
	end

	vim.bo[preview_bufnr].modifiable = true
	api.nvim_buf_set_lines(preview_bufnr, 0, -1, false, lines)
	vim.bo[preview_bufnr].modifiable = false

	for winid, cursor in pairs(win_cursors) do
		pcall(api.nvim_win_set_cursor, winid, cursor)
	end
end

--- Whether `bufnr` currently has an open tab preview — `bufnr` may be either
--- the source buffer or the preview buffer itself.
---@param bufnr integer
---@return boolean
function M.is_open(bufnr)
	return source_to_preview[bufnr] ~= nil or preview_to_source[bufnr] ~= nil
end

--- Push the current content of `source_bufnr` into its open preview, if any.
--- No-op if `source_bufnr` has no open preview.
---@param source_bufnr integer
function M.sync(source_bufnr)
	local preview_bufnr = source_to_preview[source_bufnr]
	if preview_bufnr and api.nvim_buf_is_valid(preview_bufnr) then
		sync_content(source_bufnr, preview_bufnr)
	end
end

--- Close the tab preview associated with `bufnr` (whichever side of the
--- source/preview pair it is), if open. No-op if not open.
---@param bufnr integer
function M.close(bufnr)
	local source_bufnr = preview_to_source[bufnr] or bufnr
	local preview_bufnr = source_to_preview[source_bufnr]
	if not preview_bufnr then
		return
	end

	source_to_preview[source_bufnr] = nil
	preview_to_source[preview_bufnr] = nil
	preview_tabpage[preview_bufnr] = nil

	for _, winid in ipairs(vim.fn.win_findbuf(preview_bufnr)) do
		pcall(api.nvim_win_close, winid, true)
	end
	if api.nvim_buf_is_valid(preview_bufnr) then
		pcall(api.nvim_buf_delete, preview_bufnr, { force = true })
	end
end

--- Close any preview whose tab has been taken over by something that isn't
--- the preview buffer itself — a file explorer (neo-tree/NvimTree/oil/netrw)
--- or a real file opened with `:e`. Called from the preview-tab autocmd
--- group on buffer changes. This both matches the user expectation ("toggle
--- the preview away when I open an explorer / a file") and avoids explorers
--- choking on the preview buffer's synthetic name.
function M.handle_displacement()
	local cur_buf = api.nvim_get_current_buf()
	-- Focus is on a preview buffer itself → nothing to do.
	if preview_to_source[cur_buf] then
		return
	end
	local cur_tab = api.nvim_get_current_tabpage()
	for preview_bufnr, source_bufnr in pairs(preview_to_source) do
		if preview_tabpage[preview_bufnr] == cur_tab then
			-- Something other than the preview is now active in the preview's
			-- tab. Defer the close so we don't tear windows down in the middle
			-- of whatever autocmd (e.g. neo-tree opening) triggered this.
			vim.schedule(function()
				M.close(source_bufnr)
			end)
		end
	end
end

--- Open (or focus, if already open) a tab preview mirroring `source_bufnr`.
---@param source_bufnr integer|nil defaults to the current buffer
---@return boolean ok
function M.open(source_bufnr)
	source_bufnr = source_bufnr or api.nvim_get_current_buf()

	if not is_markdown(source_bufnr) then
		vim.notify("[mdview] current buffer is not a markdown file", vim.log.levels.WARN)
		return false
	end

	local existing = source_to_preview[source_bufnr]
	if existing and api.nvim_buf_is_valid(existing) then
		local wins = vim.fn.win_findbuf(existing)
		if wins[1] then
			api.nvim_set_current_win(wins[1])
			return true
		end
		-- buffer lingered without a window (shouldn't normally happen); reopen a tab for it
		vim.cmd("tabnew")
		api.nvim_win_set_buf(0, existing)
		return true
	end

	local source_name = api.nvim_buf_get_name(source_bufnr)
	vim.cmd("tabnew")
	local preview_bufnr = api.nvim_get_current_buf()

	-- Name must NOT start with `word://` or `word:` — on Windows a leading
	-- `mdview:` reads as a drive letter, so file explorers (neo-tree, oil,
	-- netrw) try to `tcd` into it and throw ENOENT/E344. A `[mdview preview]`
	-- prefix can't be mistaken for a drive/scheme; the (bufnr) suffix keeps
	-- it unique.
	local basename = source_name ~= "" and vim.fn.fnamemodify(source_name, ":t") or "[no name]"
	pcall(
		api.nvim_buf_set_name,
		preview_bufnr,
		("[mdview preview] %s (%d)"):format(basename, source_bufnr)
	)
	vim.bo[preview_bufnr].buftype = "nofile"
	vim.bo[preview_bufnr].bufhidden = "wipe"
	vim.bo[preview_bufnr].swapfile = false
	vim.bo[preview_bufnr].filetype = "markdown"
	vim.wo.conceallevel = 2
	vim.wo.concealcursor = "nc"

	apply_highlighting(preview_bufnr)

	source_to_preview[source_bufnr] = preview_bufnr
	preview_to_source[preview_bufnr] = source_bufnr
	preview_tabpage[preview_bufnr] = api.nvim_get_current_tabpage()

	sync_content(source_bufnr, preview_bufnr)

	-- Live-sync autocmds are created lazily, once, the first time any
	-- preview is opened — see bindings/autocmds/preview_tab_sync.lua.
	require("mdview.bindings.autocmds.preview_tab_sync").ensure_attached()

	-- Clean up bookkeeping if the preview buffer disappears some other way
	-- (:bwipeout, :tabclose, etc.) so is_open()/sync() don't operate on a
	-- stale mapping afterwards.
	api.nvim_create_autocmd("BufWipeout", {
		buffer = preview_bufnr,
		once = true,
		callback = function()
			source_to_preview[source_bufnr] = nil
			preview_to_source[preview_bufnr] = nil
			preview_tabpage[preview_bufnr] = nil
		end,
	})

	return true
end

--- Toggle: open if not open, close if open. `bufnr` may be either side of
--- the source/preview pair.
---@param bufnr integer|nil defaults to the current buffer
function M.toggle(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	if M.is_open(bufnr) then
		M.close(bufnr)
	else
		M.open(bufnr)
	end
end

return M

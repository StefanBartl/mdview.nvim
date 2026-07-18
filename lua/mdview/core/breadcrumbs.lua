---@module 'mdview.core.breadcrumbs'
-- Session breadcrumbs: while a preview session runs, record which document +
-- heading section the cursor was in and when, so after the call you have a rough
-- "what did we talk about, when" outline. Deduped on (document, heading) so a
-- new entry is added only when you actually move to a different section or file,
-- not on every cursor move. Reset per session (cleared on attach).

local M = {}

---@class mdview.Breadcrumb
---@field ts integer        # os.time() epoch seconds
---@field clock string      # "HH:MM:SS"
---@field doc string        # normalized document path
---@field heading string    # nearest heading text ("# Title"), or "(top)"
---@field line integer      # 1-based cursor line at capture

---@type mdview.Breadcrumb[]
M.entries = {}
M._last_doc = nil
M._last_heading = nil

--- Nearest ATX heading at or above `line` (1-based). Scans the buffer prefix
--- once and walks back. Returns "# Title" style text, or nil if none above.
---@param bufnr integer
---@param line integer
---@return string|nil
local function nearest_heading(bufnr, line)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, line, false)
	local in_fence = false
	-- Track fenced code so a "#" inside a code block isn't mistaken for a heading.
	-- We must scan forward to know fence state, so do a forward pass recording the
	-- last real heading at/above `line`.
	local last = nil
	for _, text in ipairs(lines) do
		if text:match("^%s*```") or text:match("^%s*~~~") then
			in_fence = not in_fence
		elseif not in_fence then
			local hashes, title = text:match("^(#+)%s+(.*)$")
			if hashes and #hashes <= 6 then
				last = ("%s %s"):format(hashes, vim.trim(title))
			end
		end
	end
	return last
end

--- Record the cursor's current document + heading, if it changed since the last
--- entry. No-op for non-markdown or unnamed buffers.
---@param bufnr integer
---@return boolean recorded
function M.record(bufnr)
	local ok, ft = pcall(function()
		return require("mdview.helper.safe_buf_get_option")(bufnr, "filetype")
	end)
	ft = ok and ft or ""
	if ft ~= "markdown" and ft ~= "md" then
		return false
	end

	local raw = vim.api.nvim_buf_get_name(bufnr)
	if not raw or raw == "" then
		return false
	end
	local doc = require("mdview.helper.normalize").path(raw) or raw

	local line = 1
	local wok, pos = pcall(vim.api.nvim_win_get_cursor, 0)
	if wok and pos and vim.api.nvim_win_get_buf(0) == bufnr then
		line = pos[1]
	end

	local heading = nearest_heading(bufnr, line) or "(top)"
	if doc == M._last_doc and heading == M._last_heading then
		return false
	end
	M._last_doc = doc
	M._last_heading = heading

	M.entries[#M.entries + 1] = {
		ts = os.time(),
		clock = tostring(os.date("%H:%M:%S")),
		doc = doc,
		heading = heading,
		line = line,
	}
	return true
end

--- Drop all recorded breadcrumbs (called on session attach).
function M.clear()
	M.entries = {}
	M._last_doc = nil
	M._last_heading = nil
end

---@return mdview.Breadcrumb[]
function M.snapshot()
	return M.entries
end

--- Render the breadcrumbs as a Markdown outline (grouped by document, one bullet
--- per visited section with its time). Used for both the scratch view and export.
---@return string[]
function M.format()
	local out = { ("# Session breadcrumbs (%s)"):format(tostring(os.date("%Y-%m-%d"))), "" }
	if #M.entries == 0 then
		out[#out + 1] = "_(no breadcrumbs recorded yet)_"
		return out
	end
	local cur_doc = nil
	for _, e in ipairs(M.entries) do
		if e.doc ~= cur_doc then
			cur_doc = e.doc
			out[#out + 1] = ("## %s"):format(vim.fn.fnamemodify(e.doc, ":t"))
		end
		out[#out + 1] = ("- %s — %s"):format(e.clock, e.heading)
	end
	return out
end

return M

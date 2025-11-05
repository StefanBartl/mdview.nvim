---@module 'mdview.autocmds.on_text_changed'
--- Setup live markdown push on insert/change events
--- Uses mdview.adapter.ws_client.send_markdown to send updates per buffer change

local api = vim.api
local ws_client = require("mdview.adapter.ws_client")
local session = require("mdview.core.session")
local safe_buf_get_option = require("mdview.helper.safe_buf_get_option")
local diff = require("mdview.utils.diff_granular")

local M = {}

---@param bufnr integer
local function on_text_changed(bufnr)
  local ft = safe_buf_get_option(bufnr, "filetype") or ""
  if ft ~= "markdown" and ft ~= "md" then return end

  local path = api.nvim_buf_get_name(bufnr)
  if path == "" then return end

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local prev = session.get(path)
  local old_lines = (prev and prev.lines) or {}
  local new_lines = lines or {}

  -- ensure no nil entries inside the table
  for i = 1, #old_lines do if old_lines[i] == nil then old_lines[i] = "" end end
  for i = 1, #new_lines do if new_lines[i] == nil then new_lines[i] = "" end end

  local diffs = diff(old_lines, new_lines)

  -- send each diff chunk immediately
  for _, d in ipairs(diffs) do
    local chunk_lines = {}
    if d.op == "replace" or d.op == "insert" then
      chunk_lines = vim.list_slice(lines, d.start + 1, d.start + (d.count or #lines))
    end
    local payload = table.concat(chunk_lines, "\n")
    ws_client.send_markdown(path, payload)
  end

  session.store(path, lines)
end

--- Setup autocmds for live push
function M.setup()
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    pattern = "*.md",
    callback = function(args) on_text_changed(args.buf) end,
  })
end

return M

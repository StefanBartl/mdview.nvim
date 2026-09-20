---@module 'mdview.bindings.autocmds.bufenter'
--- Autocmd: BufEnter snapshot handling

---@diagnostic disable: undefined-global, unused-local

local api = vim.api
local session = require("mdview.core.session")
local copy_lines = require("mdview.helper.copy_lines")
local log = require("mdview.helper.log")
local hub = require("mdview.bindings.autocmds.enter_hub")

local M = {}

-- On BufEnter, store a snapshot if not present. The hub has already checked
-- that the buffer is previewable and normalized its path.
---@internal
---@param bufnr integer
---@param norm_path string|nil
---@return nil
local function on_buf_enter(bufnr, norm_path)
  if not norm_path then
    log.debug("normalized path is nil", vim.log.levels.ERROR, "events", true)
    return
  end

  -- only store snapshot if we don't already have it
  if not session.get(norm_path) then
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    session.store(norm_path, copy_lines(lines))
    log.debug("BufEnter snapshot stored for path: " .. norm_path, nil, "bufenter", true)
  end
end

--- Register the snapshot handler with the session's BufEnter hub.
function M.attach()
  hub.register("mdview.bufenter", {
    desc = "[mdview] Snapshot on enter",
    load = function(ctx)
      on_buf_enter(ctx.buf, ctx.context.path)
    end,
  })
end

return M

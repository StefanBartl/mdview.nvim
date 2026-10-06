---@module 'tests.nvim.live_push_cost_spec'
-- push_buffer_changes runs on every throttled TextChanged(I), i.e. every ~150 ms
-- while typing, on the main loop. It used to store a session snapshot through
-- session.store, which hashed the whole document (concat + sha256) on every
-- push although nothing reads the hash: ~0.5 ms at 2k lines, ~20 ms at 100k.
-- The push must stay O(text sent), with no extra full-document pass.

---@diagnostic disable: undefined-global, duplicate-set-field

local ws = require("mdview.adapter.ws_client")
local live = require("mdview.bindings.autocmds.live_push")
local session = require("mdview.core.session")
local normalize = require("mdview.helper.normalize")

describe("live_push.push_buffer_changes cost", function()
  it("does not hash the document on a push, but still stores the snapshot", function()
    local orig_send_content, orig_send_doc = ws.send_content, ws.send_doc
    local real_sha256 = vim.fn.sha256
    local sent_lines
    local hash_calls = 0
    ws.send_content = function(_, lines)
      sent_lines = lines
    end
    ws.send_doc = function() end
    vim.fn.sha256 = function(text)
      hash_calls = hash_calls + 1
      return real_sha256(text)
    end

    local buf = vim.api.nvim_create_buf(true, false)
    local ok, err = pcall(function()
      vim.api.nvim_buf_set_name(buf, "mdview_spec_live_push_cost.md")
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# doc", "body", "more body" })
      local key = normalize.path(vim.api.nvim_buf_get_name(buf))

      session.init()
      live.push_buffer_changes(buf)
      live.push_buffer_changes(buf)
      live.push_buffer_changes(buf)

      assert.are.same({ "# doc", "body", "more body" }, sent_lines)
      assert.are.equal(0, hash_calls, "a push must not hash the whole document")

      local entry = session.get(key)
      assert(entry, "the snapshot is still stored under the normalized path")
      assert.are.same({ "# doc", "body", "more body" }, entry.lines)
    end)

    ws.send_content, ws.send_doc = orig_send_content, orig_send_doc
    vim.fn.sha256 = real_sha256
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    if not ok then
      error(err, 0)
    end
  end)
end)

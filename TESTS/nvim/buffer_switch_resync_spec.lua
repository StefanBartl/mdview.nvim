---@module 'tests.nvim.buffer_switch_resync_spec'
-- M.resync (browser.behavior = "reuse") captures `bufnr` before handing off
-- to ws_client.wait_ready, which is async and can take up to
-- WAIT_READY_TIMEOUT (15s) on a slow/first-run relay start. If the buffer is
-- wiped while that health check is still polling, the wait_ready callback
-- used to call nvim_buf_get_lines(bufnr, ...) on an already-invalid handle,
-- throwing "Invalid buffer id" instead of quietly skipping the stale push
-- (ERR-33: defer_fn/schedule callbacks must re-validate handles at execution
-- time, not just capture time).

---@diagnostic disable: undefined-global, duplicate-set-field

local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local buffer_switch = require("mdview.bindings.autocmds.buffer_switch")

describe("buffer_switch.resync with a buffer invalidated mid-wait", function()
  it("does not error and does not push stale content once the buffer is gone", function()
    local orig_wait_ready = ws.wait_ready
    local orig_send_content = ws.send_content

    local captured_cb
    ws.wait_ready = function(cb)
      -- Simulate the real async gap: don't call cb yet, just remember it,
      -- as if the relay were still mid-health-check-poll.
      captured_cb = cb
    end

    local sent = false
    ws.send_content = function()
      sent = true
    end

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "mdview_spec_resync_stale.md")
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# doc" })

    state.set_preview_key("some/other/preview/room.md")

    local started = buffer_switch.resync(buf)
    assert.is_true(started)
    assert.is_true(type(captured_cb) == "function")

    -- The buffer goes away while the (fake) health check is still pending.
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_false(vim.api.nvim_buf_is_valid(buf))

    -- Now the relay "answers" — this must not throw on the stale handle.
    local ok, err = pcall(captured_cb, true)
    assert.is_true(ok, tostring(err))
    assert.is_false(sent)

    ws.wait_ready = orig_wait_ready
    ws.send_content = orig_send_content
  end)
end)

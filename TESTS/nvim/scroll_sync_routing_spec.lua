---@module 'tests.nvim.scroll_sync_routing_spec'
-- Regression test for the bug where scroll_sync always sent the outgoing
-- scroll/cursor ping to the buffer's own path, even in browser.behavior
-- "reuse" where the open tab actually watches state.preview_key — so after
-- switching buffers, pings landed in a room nobody was listening to and the
-- cursor marker ("rides the scroll-sync ping") silently stopped updating,
-- even though live_push and :MDView cursor (control.lua) routed correctly.
-- Mirrors buffer_switch_spec.lua's coverage of live_push, now for
-- scroll_sync via the shared mdview.helper.target_key resolver both use.

---@diagnostic disable: undefined-global

local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")
local bcfg = require("mdview.config.browser")
local normalize = require("mdview.helper.normalize")

-- Capture where the scroll ping is routed. send_current_position calls
-- ws_client.send_scroll(target, ...); stub it.
local last_key
local orig = ws.send_scroll
ws.send_scroll = function(key)
  last_key = key
end

local function make_md_buffer(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# doc", "body" })
  return buf
end

describe("scroll_sync routing by browser.behavior", function()
  local buf = make_md_buffer("mdview_spec_scroll_B.md")
  local B_key = normalize.path(vim.api.nvim_buf_get_name(buf))
  local PREVIEW_KEY = "some/other/preview/room.md"

  -- send_current_position reads the current window's cursor (api.nvim_win_get_cursor(0)),
  -- so make buf the current buffer for these calls.
  vim.api.nvim_set_current_buf(buf)

  it("reuse -> targets the open tab's preview key, not the buffer's own path", function()
    state.set_preview_key(PREVIEW_KEY)
    bcfg.defaults.behavior = "reuse"
    last_key = nil
    scroll_sync.send_current_position(buf)
    assert.are.equal(PREVIEW_KEY, last_key)
  end)

  it("new_tab -> targets the buffer's own path", function()
    state.set_preview_key(PREVIEW_KEY)
    bcfg.defaults.behavior = "new_tab"
    last_key = nil
    scroll_sync.send_current_position(buf)
    assert.are.equal(B_key, last_key)
  end)

  it("manual -> targets the buffer's own path", function()
    bcfg.defaults.behavior = "manual"
    last_key = nil
    scroll_sync.send_current_position(buf)
    assert.are.equal(B_key, last_key)
  end)

  it("reuse with no open tab -> falls back to the buffer's path", function()
    state.set_preview_key(nil)
    bcfg.defaults.behavior = "reuse"
    last_key = nil
    scroll_sync.send_current_position(buf)
    assert.are.equal(B_key, last_key)
  end)

  -- restore
  ws.send_scroll = orig
end)

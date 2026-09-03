---@module 'tests.nvim.pin_spec'
-- Verifies document pinning (mdview.core.pin, :MDView pin).
--
-- The whole point of a pin is asymmetric: traffic from OTHER buffers that
-- would land in the pinned tab's room is dropped, while the pinned document's
-- own traffic and any traffic with a room of its own still goes through. Both
-- halves are covered here, on the two channels that carry them (live_push's
-- content push and scroll_sync's cursor ping), because getting only the first
-- half right turns a pin into a global mute.

---@diagnostic disable: undefined-global

local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local pin = require("mdview.core.pin")
local live = require("mdview.bindings.autocmds.live_push")
local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")
local buffer_switch = require("mdview.bindings.autocmds.buffer_switch")
local bcfg = require("mdview.config.browser")
local normalize = require("mdview.helper.normalize")

-- Capture where each channel routes (or that it sent nothing at all).
local last_content, last_scroll
local orig_content, orig_scroll = ws.send_content, ws.send_scroll
---@diagnostic disable-next-line: duplicate-set-field
ws.send_content = function(key)
  last_content = key
end
---@diagnostic disable-next-line: duplicate-set-field
ws.send_scroll = function(key)
  last_scroll = key
end

local function make_md_buffer(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# doc", "body" })
  return buf
end

describe("mdview.core.pin", function()
  -- Plain relative names, resolved through nvim, so the keys match on both
  -- Windows and Linux (see buffer_switch_spec.lua for why).
  local pinned_buf = make_md_buffer("mdview_spec_pin_A.md")
  local other_buf = make_md_buffer("mdview_spec_pin_B.md")
  local A_key = normalize.path(vim.api.nvim_buf_get_name(pinned_buf))
  local B_key = normalize.path(vim.api.nvim_buf_get_name(other_buf))
  local PREVIEW_KEY = "some/other/preview/room.md"

  -- scroll_sync reads the CURRENT window's cursor, so the buffer under test
  -- has to be the current one when its ping is sent.
  local function with_current(buf, fn)
    local prev = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(buf)
    fn()
    -- Only restore a buffer that still exists: earlier specs create scratch
    -- buffers and wipe them, so the one that happened to be current here can
    -- already be gone by the time this runs.
    if vim.api.nvim_buf_is_valid(prev) then
      vim.api.nvim_set_current_buf(prev)
    end
  end

  it("blocks nothing while unpinned", function()
    pin.clear()
    bcfg.defaults.behavior = "reuse"
    state.set_preview_key(PREVIEW_KEY)
    assert.is_false(pin.blocks(other_buf))
  end)

  it("pins the given buffer's normalized path", function()
    assert.are.equal(A_key, pin.set(pinned_buf))
    assert.is_true(pin.is_pinned())
    assert.are.equal(A_key, pin.get())
  end)

  it("reuse -> blocks another buffer, which shares the pinned tab's room", function()
    bcfg.defaults.behavior = "reuse"
    state.set_preview_key(PREVIEW_KEY)
    pin.set(pinned_buf)
    assert.is_true(pin.blocks(other_buf))
  end)

  it("reuse -> never blocks the pinned document itself", function()
    bcfg.defaults.behavior = "reuse"
    state.set_preview_key(PREVIEW_KEY)
    pin.set(pinned_buf)
    assert.is_false(pin.blocks(pinned_buf))
  end)

  it("new_tab -> blocks nothing: every document has a room of its own", function()
    bcfg.defaults.behavior = "new_tab"
    state.set_preview_key(PREVIEW_KEY)
    pin.set(pinned_buf)
    assert.is_false(pin.blocks(other_buf))
  end)

  it("drops the content push of a blocked buffer", function()
    bcfg.defaults.behavior = "reuse"
    state.set_preview_key(PREVIEW_KEY)
    pin.set(pinned_buf)
    last_content = nil
    live.push_buffer_changes(other_buf)
    assert.is_nil(last_content)
  end)

  it("still pushes the pinned document's own edits", function()
    bcfg.defaults.behavior = "reuse"
    state.set_preview_key(PREVIEW_KEY)
    pin.set(pinned_buf)
    last_content = nil
    live.push_buffer_changes(pinned_buf)
    assert.are.equal(PREVIEW_KEY, last_content)
  end)

  it("drops the scroll ping of a blocked buffer", function()
    bcfg.defaults.behavior = "reuse"
    state.set_preview_key(PREVIEW_KEY)
    pin.set(pinned_buf)
    last_scroll = nil
    with_current(other_buf, function()
      scroll_sync.send_current_position(other_buf)
    end)
    assert.is_nil(last_scroll)
  end)

  it("still sends the pinned document's own scroll ping", function()
    bcfg.defaults.behavior = "reuse"
    state.set_preview_key(PREVIEW_KEY)
    pin.set(pinned_buf)
    last_scroll = nil
    with_current(pinned_buf, function()
      scroll_sync.send_current_position(pinned_buf)
    end)
    assert.are.equal(PREVIEW_KEY, last_scroll)
  end)

  it("lets a blocked buffer through again once released", function()
    bcfg.defaults.behavior = "reuse"
    state.set_preview_key(PREVIEW_KEY)
    pin.set(pinned_buf)
    assert.are.equal(A_key, pin.clear())
    last_content = nil
    live.push_buffer_changes(other_buf)
    assert.are.equal(PREVIEW_KEY, last_content)
  end)

  it("follow() moves a live pin and is a no-op without one", function()
    pin.clear()
    assert.is_nil(pin.follow(other_buf))
    assert.is_false(pin.is_pinned())

    pin.set(pinned_buf)
    assert.are.equal(B_key, pin.follow(other_buf))
    assert.are.equal(B_key, pin.get())
  end)

  it("resync reports that there is no open tab to catch up", function()
    pin.clear()
    state.set_preview_key(nil)
    assert.is_false(buffer_switch.resync(other_buf))
  end)

  -- restore: a leaked pin would silently swallow every later spec's pushes.
  pin.clear()
  state.set_preview_key(nil)
  bcfg.defaults.behavior = "reuse"
  ws.send_content = orig_content
  ws.send_scroll = orig_scroll
end)

-- The real BufEnter path, not just the gate it consults: a pin is only worth
-- anything if the autocmd that makes the tab follow the active buffer actually
-- stops firing while one is up -- and if releasing it puts the tab back on the
-- buffer you are in, rather than leaving it on the released document.
describe("buffer_switch under a document pin", function()
  local pinned_buf = make_md_buffer("mdview_spec_pin_switch_A.md")
  local other_buf = make_md_buffer("mdview_spec_pin_switch_B.md")
  local PREVIEW_KEY = "some/other/preview/room.md"

  local pushed
  local orig_wait, orig_send = ws.wait_ready, ws.send_content
  -- Readiness is a live /health probe; short-circuit it so the push is
  -- synchronous and the assertion below doesn't race a timer.
  ---@diagnostic disable-next-line: duplicate-set-field
  ws.wait_ready = function(cb)
    cb(true)
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  ws.send_content = function(key)
    pushed = key
  end

  state.set_server({ stub = true })
  state.set_preview_key(PREVIEW_KEY)
  bcfg.defaults.behavior = "reuse"

  local group = vim.api.nvim_create_augroup("MdviewPinSwitchSpec", { clear = true })
  buffer_switch.attach(group)

  --- Enter `buf` the way a user would, so BufEnter really fires.
  local function enter(buf)
    pushed = nil
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
  end

  it("unpinned -> a switch moves the tab to the entered buffer", function()
    pin.clear()
    buffer_switch.reset()
    enter(pinned_buf)
    enter(other_buf)
    assert.are.equal(PREVIEW_KEY, pushed)
  end)

  it("pinned -> a switch pushes nothing at all", function()
    buffer_switch.reset()
    enter(pinned_buf)
    pin.set(pinned_buf)
    enter(other_buf)
    assert.is_nil(pushed)
  end)

  it("releasing the pin catches the tab up with the current buffer", function()
    pin.set(pinned_buf)
    vim.api.nvim_set_current_buf(other_buf)
    pushed = nil
    -- Through the user command, so the whole :MDView pin off path is covered.
    local orig_notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
    require("mdview.bindings.usrcmds.pin").run("off")
    vim.notify = orig_notify
    assert.is_false(pin.is_pinned())
    assert.are.equal(PREVIEW_KEY, pushed)
  end)

  -- restore
  vim.api.nvim_del_augroup_by_id(group)
  pin.clear()
  state.set_server(nil)
  state.set_preview_key(nil)
  ws.wait_ready = orig_wait
  ws.send_content = orig_send
end)

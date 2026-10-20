---@module 'tests.nvim.usrcmds_write_spec'
-- :MDView write [on|off|toggle] switches the cursor caret and block editing
-- together, starts the preview when none runs, and never stops it. Plus the
-- opt-in `keymaps.write` mapping (no keymap by default).
--
-- Collaborators are stubbed at their one real definition: control.send (live
-- update), start.run / stop.run (session lifecycle), the same convention as
-- usrcmds_preview_controls_spec.lua.

---@diagnostic disable: undefined-global, duplicate-set-field

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")
local cfg = require("mdview.config")
local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")
local inbound_poll = require("mdview.adapter.inbound_poll")
local start = require("mdview.bindings.usrcmds.start")
local stop = require("mdview.bindings.usrcmds.stop")
local write = require("mdview.bindings.usrcmds.write")
local keymaps = require("mdview.bindings.keymaps")

local orig = {
  notify = vim.notify,
  send = control.send,
  ping = scroll_sync.send_current_position,
  poll_start = inbound_poll.start,
  start_run = start.run,
  stop_run = stop.run,
  stop_stop = stop.stop,
}

local sent, sends, started, stopped, poll_started
vim.notify = function() end
control.send = function(fields)
  sent = fields
  sends = sends + 1
  return true
end
scroll_sync.send_current_position = function() end
inbound_poll.start = function()
  poll_started = true
end
start.run = function(fargs)
  started = fargs
end
stop.run = function()
  stopped = true
end
stop.stop = function()
  stopped = true
end

local function reset(marker, edit, server)
  write._reset()
  cfg.defaults.browser.cursor_marker = marker
  cfg.defaults.edit_blocks = edit
  state.set_server(server)
  sent, sends, started, stopped, poll_started = nil, 0, nil, nil, nil
end

describe("usrcmds.write", function()
  after_each(function()
    state.set_server(nil)
  end)

  it("on without a session sets both, then starts the preview", function()
    reset("line", false, nil)
    write.run("on")
    assert.are.equal("caret", cfg.defaults.browser.cursor_marker)
    assert.is_true(cfg.defaults.edit_blocks)
    assert.are.same({}, started)
    assert.are.equal(0, sends)
  end)

  it("toggle without a session starts the preview with both on", function()
    reset("section", false, nil)
    write.run()
    assert.is_true(write.is_on())
    assert.is_not_nil(started)
  end)

  it("on with a session pushes ONE control update and does not restart", function()
    reset("line", false, { stub = true })
    write.run("on")
    assert.are.equal(1, sends)
    assert.are.same({ cursor = "caret", editBlocks = true }, sent)
    assert.is_true(poll_started)
    assert.is_nil(started)
  end)

  it("off never stops the session and restores the earlier marker", function()
    reset("section", false, { stub = true })
    write.run("on")
    write.run("off")
    assert.is_nil(stopped)
    assert.is_not_nil(state.get_server())
    assert.are.equal("section", cfg.defaults.browser.cursor_marker)
    assert.is_false(cfg.defaults.edit_blocks)
    assert.are.same({ cursor = "section", editBlocks = false }, sent)
  end)

  it("a configured 'block' marker: on switches to caret (never forces block), off brings block back", function()
    reset("block", false, { stub = true })
    write.run("on")
    assert.are.equal("caret", cfg.defaults.browser.cursor_marker)
    assert.are.same({ cursor = "caret", editBlocks = true }, sent)
    write.run("off")
    assert.are.equal("block", cfg.defaults.browser.cursor_marker)
    assert.are.same({ cursor = "block", editBlocks = false }, sent)
  end)

  it("toggle twice with a session: on, then off, preview still running", function()
    reset("line", false, { stub = true })
    write.run("toggle")
    assert.is_true(write.is_on())
    write.run("toggle")
    assert.is_false(write.is_on())
    assert.is_nil(stopped)
    assert.is_nil(started)
    assert.are.equal("line", cfg.defaults.browser.cursor_marker)
  end)

  it("off without a session records the choice and starts nothing", function()
    reset("caret", true, nil)
    write.run("off")
    assert.is_nil(started)
    assert.is_false(cfg.defaults.edit_blocks)
    assert.are_not.equal("caret", cfg.defaults.browser.cursor_marker)
  end)

  it("off keeps a non-caret marker (only block editing was on)", function()
    reset("section", true, { stub = true })
    write.run("off")
    assert.are.equal("section", cfg.defaults.browser.cursor_marker)
    assert.is_false(cfg.defaults.edit_blocks)
    assert.are.same({ cursor = "section", editBlocks = false }, sent)
  end)

  it("off keeps a marker the user picked after on", function()
    reset("line", false, { stub = true })
    write.run("on")
    cfg.defaults.browser.cursor_marker = "section" -- e.g. :MDView cursor section
    write.run("off")
    assert.are.equal("section", cfg.defaults.browser.cursor_marker)
    assert.is_false(cfg.defaults.edit_blocks)
  end)

  it("toggle from a mixed state (only edit on) switches both on", function()
    reset("line", true, { stub = true })
    write.run("toggle")
    assert.is_true(write.is_on())
  end)

  it("toggle from a mixed state (only caret on) switches both on", function()
    reset("caret", false, { stub = true })
    write.run("toggle")
    assert.is_true(write.is_on())
  end)

  it("rejects an unknown action without mutating anything", function()
    reset("line", false, { stub = true })
    write.run("sideways")
    assert.are.equal("line", cfg.defaults.browser.cursor_marker)
    assert.is_false(cfg.defaults.edit_blocks)
    assert.are.equal(0, sends)
  end)
end)

describe("bindings.keymaps", function()
  it("maps nothing by default", function()
    assert.are.same({}, keymaps.attach(cfg.defaults.keymaps))
    assert.are.same({}, keymaps.attach(nil))
    assert.are.same({}, keymaps.attach({ write = false }))
  end)

  it("maps keymaps.write to :MDView write toggle", function()
    reset("line", false, { stub = true })
    local lhs = "<Plug>(mdview-write-spec)"
    assert.are.same({ lhs }, keymaps.attach({ write = lhs }))
    local map = vim.fn.maparg(lhs, "n", false, true)
    assert.is_function(map.callback)
    map.callback()
    assert.is_true(write.is_on())
    vim.keymap.del("n", lhs)
  end)

  it("setup() accepts keymaps.write without an unknown-key warning", function()
    local warned
    vim.notify = function(msg)
      warned = msg
    end
    cfg.validate({ keymaps = { write = "<leader>mw" } })
    vim.notify = function() end
    assert.is_nil(warned)
  end)
end)

vim.notify = orig.notify
control.send = orig.send
scroll_sync.send_current_position = orig.ping
inbound_poll.start = orig.poll_start
start.run = orig.start_run
stop.run = orig.stop_run
stop.stop = orig.stop_stop
cfg.defaults.browser.cursor_marker = "line"
cfg.defaults.edit_blocks = false

---@module 'tests.nvim.usrcmds_preview_controls_spec'
-- Covers the "live preview control" family of :MDView actions: each records a
-- choice into the shared browser config (so it applies on the next
-- :MDView start) and, when a session is already running, pushes a live
-- /control update instead of waiting for a reload. None of these had any
-- coverage before -- every existing spec reaches mdview.adapter.control only
-- transitively through selection_sync/scroll_sync.
--
-- control.send is stubbed at its one real definition (mdview.adapter.control),
-- which every action module below requires and calls through -- the same
-- collaborator-stubbing convention as ws_client.send_content in pin_spec.lua.

---@diagnostic disable: undefined-global, duplicate-set-field

local control = require("mdview.adapter.control")
local state = require("mdview.core.state")
local bcfg = require("mdview.config.browser")

local blanklines = require("mdview.bindings.usrcmds.blanklines")
local cursor = require("mdview.bindings.usrcmds.cursor")
local overlay = require("mdview.bindings.usrcmds.overlay")
local reveal = require("mdview.bindings.usrcmds.reveal")
local selection = require("mdview.bindings.usrcmds.selection")
local sync = require("mdview.bindings.usrcmds.sync")
local zoom = require("mdview.bindings.usrcmds.zoom")
local theme = require("mdview.bindings.usrcmds.theme")

-- Silence every notify() in this file -- these actions notify on every call,
-- and the assertions below are about state/control, not message wording.
local orig_notify = vim.notify
vim.notify = function() end

local sent
local orig_control_send = control.send
control.send = function(fields)
  sent = fields
  return true
end

describe("usrcmds.blanklines", function()
  it("records the choice without a session, without calling control.send", function()
    state.set_server(nil)
    bcfg.defaults.preserve_blank_lines = false
    sent = nil
    blanklines.run("on")
    assert.is_true(bcfg.defaults.preserve_blank_lines)
    assert.is_nil(sent)
  end)

  it("pushes a live control update once a session is running", function()
    state.set_server({ stub = true })
    sent = nil
    blanklines.run("off")
    assert.is_false(bcfg.defaults.preserve_blank_lines)
    assert.are.same({ blankLines = false }, sent)
    state.set_server(nil)
  end)

  it("toggle flips the current value", function()
    state.set_server(nil)
    bcfg.defaults.preserve_blank_lines = false
    blanklines.run("toggle")
    assert.is_true(bcfg.defaults.preserve_blank_lines)
    blanklines.run() -- no-arg toggles too
    assert.is_false(bcfg.defaults.preserve_blank_lines)
  end)

  it("rejects an unknown action without mutating anything", function()
    bcfg.defaults.preserve_blank_lines = true
    blanklines.run("sideways")
    assert.is_true(bcfg.defaults.preserve_blank_lines)
  end)
end)

describe("usrcmds.cursor", function()
  it("reports the current mode without mutating when given no argument", function()
    bcfg.defaults.cursor_marker = "line"
    cursor.run(nil)
    assert.are.equal("line", bcfg.defaults.cursor_marker)
  end)

  it("toggle flips between 'section' and 'off'", function()
    bcfg.defaults.cursor_marker = "line"
    cursor.run("toggle")
    assert.are.equal("section", bcfg.defaults.cursor_marker)
    cursor.run("toggle")
    assert.are.equal("off", bcfg.defaults.cursor_marker)
  end)

  it("sets a valid explicit mode and pushes it live when a session exists", function()
    state.set_server({ stub = true })
    sent = nil
    cursor.run("caret")
    assert.are.equal("caret", bcfg.defaults.cursor_marker)
    assert.are.same({ cursor = "caret" }, sent)
    state.set_server(nil)
  end)

  it("rejects an unknown mode without mutating", function()
    bcfg.defaults.cursor_marker = "line"
    cursor.run("bogus")
    assert.are.equal("line", bcfg.defaults.cursor_marker)
  end)
end)

describe("usrcmds.overlay", function()
  it("lists known overlays without erroring when given no name", function()
    local ok, err = pcall(overlay.run, nil, nil)
    assert.is_true(ok, tostring(err))
  end)

  it("rejects an unknown overlay name", function()
    bcfg.defaults.overlays = { toc = false }
    overlay.run("nope", "on")
    assert.is_false(bcfg.defaults.overlays.toc)
  end)

  it("toggles a known overlay and pushes it live when a session exists", function()
    state.set_server({ stub = true })
    bcfg.defaults.overlays = { toc = false }
    sent = nil
    overlay.run("toc", "on")
    assert.is_true(bcfg.defaults.overlays.toc)
    assert.are.same({ overlay = { name = "toc", on = true } }, sent)
    state.set_server(nil)
  end)

  it("default action is toggle", function()
    bcfg.defaults.overlays = { toc = false }
    state.set_server(nil)
    overlay.run("toc")
    assert.is_true(bcfg.defaults.overlays.toc)
  end)
end)

describe("usrcmds.reveal", function()
  it("refuses to run without a session", function()
    state.set_server(nil)
    sent = nil
    reveal.run("on")
    assert.is_nil(sent)
  end)

  it("sends {reveal=true}/{reveal=false} and tracks the mirrored state", function()
    state.set_server({ stub = true })
    reveal._revealed = false
    sent = nil
    reveal.run("on")
    assert.are.same({ reveal = true }, sent)
    assert.is_true(reveal._revealed)

    reveal.run("toggle")
    assert.are.same({ reveal = false }, sent)
    assert.is_false(reveal._revealed)
    state.set_server(nil)
  end)
end)

describe("usrcmds.sync", function()
  local scroll_sync = require("mdview.bindings.autocmds.scroll_sync")

  it("pause/resume/toggle drive scroll_sync's pause switch", function()
    scroll_sync.set_paused(false)
    sync.run("pause")
    assert.is_true(scroll_sync.is_paused())
    sync.run("resume")
    assert.is_false(scroll_sync.is_paused())
    sync.run("toggle")
    assert.is_true(scroll_sync.is_paused())
    scroll_sync.set_paused(false)
  end)

  it("reports without mutating when given no argument", function()
    scroll_sync.set_paused(true)
    local ok = pcall(sync.run, nil)
    assert.is_true(ok)
    assert.is_true(scroll_sync.is_paused())
    scroll_sync.set_paused(false)
  end)
end)

describe("usrcmds.zoom", function()
  it("+ / - step by 0.1 and clamp to [0.5, 3.0]", function()
    bcfg.defaults.zoom = 1.0
    zoom.run("+")
    assert.are.equal(1.1, bcfg.defaults.zoom)
    zoom.run("-")
    zoom.run("-")
    assert.are.equal(0.9, bcfg.defaults.zoom)
  end)

  it("reset sets exactly 1.0", function()
    bcfg.defaults.zoom = 2.5
    zoom.run("reset")
    assert.are.equal(1.0, bcfg.defaults.zoom)
  end)

  it("accepts a percentage above 5 and converts it to a factor", function()
    zoom.run("150")
    assert.are.equal(1.5, bcfg.defaults.zoom)
  end)

  it("accepts a bare factor at or below 5", function()
    zoom.run("2")
    assert.are.equal(2.0, bcfg.defaults.zoom)
  end)

  it("clamps an out-of-range value instead of applying it verbatim", function()
    zoom.run("500")
    assert.are.equal(3.0, bcfg.defaults.zoom)
    zoom.run("10") -- 10 > 5 -> treated as 10% -> clamped up to MIN 0.5
    assert.are.equal(0.5, bcfg.defaults.zoom)
  end)

  it("rejects a non-numeric argument without mutating", function()
    bcfg.defaults.zoom = 1.2
    zoom.run("banana")
    assert.are.equal(1.2, bcfg.defaults.zoom)
  end)

  it("pushes the new zoom live when a session exists", function()
    state.set_server({ stub = true })
    bcfg.defaults.zoom = 1.0
    sent = nil
    zoom.run("+")
    assert.are.same({ zoom = 1.1 }, sent)
    state.set_server(nil)
  end)
end)

describe("usrcmds.selection", function()
  local selection_sync = require("mdview.bindings.autocmds.selection_sync")

  it("records the choice without a session", function()
    state.set_server(nil)
    bcfg.defaults.selection_sync = false
    selection.run("on")
    assert.is_true(bcfg.defaults.selection_sync)
  end)

  it("resets the dedup cache and pushes selectionSync live when a session exists", function()
    -- An unnamed buffer fails previewable.is (empty name), so the follow-up
    -- selection_sync.send_current_selection() below is a no-op and the ONLY
    -- observable control.send is selection.run's own {selectionSync=on}.
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    state.set_server({ stub = true })
    bcfg.defaults.selection_sync = false
    selection_sync.reset()
    sent = nil
    selection.run("on")
    assert.is_true(bcfg.defaults.selection_sync)
    assert.are.same({ selectionSync = true }, sent)
    state.set_server(nil)
  end)
end)

describe("usrcmds.theme", function()
  it("rejects an unknown theme name without mutating", function()
    bcfg.defaults.theme = "github"
    theme.run("not-a-real-theme")
    assert.are.equal("github", bcfg.defaults.theme)
  end)

  it("accepts a known theme with a -light/-dark suffix", function()
    theme.run("tokyonight-dark")
    assert.are.equal("tokyonight-dark", bcfg.defaults.theme)
  end)

  it("records the choice for next start without a session, without reopening", function()
    state.set_server(nil)
    local mdview = require("mdview")
    local open_called = false
    local orig_open = mdview.open
    mdview.open = function()
      open_called = true
    end
    theme.run("plain")
    assert.are.equal("plain", bcfg.defaults.theme)
    assert.is_false(open_called)
    mdview.open = orig_open
  end)

  it("re-opens the preview when a full session is attached and not tab-mode", function()
    local mdview = require("mdview")
    local open_called = false
    local orig_open = mdview.open
    mdview.open = function()
      open_called = true
    end
    state.set_server({ stub = true })
    state.set_attached(true)
    require("mdview.config").defaults.open_preview_tab = false
    theme.run("catppuccin")
    assert.is_true(open_called)
    mdview.open = orig_open
    state.set_server(nil)
    state.set_attached(false)
  end)

  it("does not reopen in tab-preview mode", function()
    local mdview = require("mdview")
    local open_called = false
    local orig_open = mdview.open
    mdview.open = function()
      open_called = true
    end
    state.set_server({ stub = true })
    state.set_attached(true)
    require("mdview.config").defaults.open_preview_tab = true
    theme.run("github")
    assert.is_false(open_called)
    mdview.open = orig_open
    require("mdview.config").defaults.open_preview_tab = false
    state.set_server(nil)
    state.set_attached(false)
  end)
end)

control.send = orig_control_send
vim.notify = orig_notify

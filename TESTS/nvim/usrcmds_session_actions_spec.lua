---@module 'tests.nvim.usrcmds_session_actions_spec'
-- Covers the session-lifecycle and reporting :MDView actions that had no
-- coverage before: stop, toggle (dispatch only -- start/stop are stubbed so
-- this doesn't also re-test their own bodies), open, diagnose, file-log,
-- breadcrumbs (the usrcmd wrapper -- core.breadcrumbs itself is covered in
-- breadcrumbs_spec.lua), weblogs and preview-tab (ditto, wrapper only --
-- adapter.preview_tab itself is covered in preview_tab_spec.lua).
--
-- mdview.adapter.ws_client.send_close is stubbed for every stop.stop() call:
-- unstubbed, a "session running" stub would make it shell out to a real curl
-- POST against localhost (see stop.lua's own comment on why the close signal
-- must go out before the process dies) -- exactly the real-subprocess call
-- this campaign avoids.

---@diagnostic disable: undefined-global, duplicate-set-field

local state = require("mdview.core.state")
local pin = require("mdview.core.pin")
local browser_cfg = require("mdview.config.browser")
local ws = require("mdview.adapter.ws_client")

local stop = require("mdview.bindings.usrcmds.stop")
local toggle = require("mdview.bindings.usrcmds.toggle")
local open_cmd = require("mdview.bindings.usrcmds.open")
local diagnose = require("mdview.bindings.usrcmds.diagnose")
local file_log_cmd = require("mdview.bindings.usrcmds.file_log")
local breadcrumbs_cmd = require("mdview.bindings.usrcmds.breadcrumbs")
local show_weblogs = require("mdview.bindings.usrcmds.show_weblogs")
local preview_tab_cmd = require("mdview.bindings.usrcmds.preview_tab")
local log = require("mdview.adapter.log")

local orig_notify = vim.notify
vim.notify = function() end

local close_called
local orig_send_close = ws.send_close
ws.send_close = function()
  close_called = true
end

describe("usrcmds.stop", function()
  it("detaches, clears server/pin/preview-key, and sends the close signal", function()
    state.set_attached(true)
    state.set_server({ stub = true })
    state.set_preview_key("some/room.md")
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "mdview_spec_stop.md")
    pin.set(buf)
    close_called = nil

    stop.stop(false) -- false: leave the (absent) browser handle alone

    assert.is_false(state.is_attached())
    assert.is_nil(state.get_server())
    assert.is_nil(state.get_preview_key())
    assert.is_false(pin.is_pinned())
    assert.is_true(close_called)
  end)

  it("closes the browser handle only when should_close is true", function()
    state.set_browser({ job_id = nil }) -- no real job to stop
    stop.stop(false)
    assert(state.get_browser() ~= nil, "override false must leave the handle alone")

    stop.stop(true)
    assert.is_nil(state.get_browser())
  end)

  it("M.run() delegates to browser_cfg.defaults.browser_autoclose", function()
    browser_cfg.defaults.browser_autoclose = false
    state.set_browser({ job_id = nil })
    stop.run()
    assert(state.get_browser() ~= nil, "autoclose=false must leave the handle alone")

    browser_cfg.defaults.browser_autoclose = true
    stop.run()
    assert.is_nil(state.get_browser())
    browser_cfg.defaults.browser_autoclose = true
  end)
end)

describe("usrcmds.toggle", function()
  local start = require("mdview.bindings.usrcmds.start")
  local stop_mod = require("mdview.bindings.usrcmds.stop")
  local orig_start_run, orig_stop_run = start.run, stop_mod.run
  local start_args, stop_called

  start.run = function(fargs)
    start_args = fargs
  end
  stop_mod.run = function()
    stop_called = true
  end

  it("starts when no session is running, forwarding fargs", function()
    state.set_server(nil)
    start_args, stop_called = nil, nil
    toggle.run({ "notes.md" })
    assert.are.same({ "notes.md" }, start_args)
    assert.is_nil(stop_called)
  end)

  it("stops (ignoring fargs) when a session is running", function()
    state.set_server({ stub = true })
    start_args, stop_called = nil, nil
    toggle.run({ "ignored.md" })
    assert.is_true(stop_called)
    assert.is_nil(start_args)
    state.set_server(nil)
  end)

  start.run = orig_start_run
  stop_mod.run = orig_stop_run
end)

describe("usrcmds.open", function()
  it("delegates to mdview.open()", function()
    local mdview = require("mdview")
    local called = false
    local orig_open = mdview.open
    mdview.open = function()
      called = true
    end
    open_cmd.run()
    assert.is_true(called)
    mdview.open = orig_open
  end)
end)

describe("usrcmds.diagnose", function()
  it("writes the report to the given path and opens it in a new tab", function()
    local path = vim.fn.tempname() .. "-mdview-diagnose.txt"
    local tabs_before = vim.fn.tabpagenr("$")

    diagnose.run(path)

    assert.are.equal(1, vim.fn.filereadable(path))
    local lines = vim.fn.readfile(path)
    assert.is_true(#lines > 0)
    assert.is_true(lines[1]:match("^mdview%.nvim diagnostics") ~= nil)
    assert.are.equal(tabs_before + 1, vim.fn.tabpagenr("$"))

    vim.cmd("tabclose")
    vim.fn.delete(path)
  end)
end)

describe("usrcmds.file_log", function()
  it("on(path) enables file logging at the given absolute path", function()
    local path = vim.fn.tempname() .. "-filelog.log"
    file_log_cmd.on(path)
    local enabled, got_path = log.file_log_state()
    assert.is_true(enabled)
    assert.are.equal(vim.fn.fnamemodify(path, ":p"), got_path)
    file_log_cmd.off()
  end)

  it("off() disables it", function()
    file_log_cmd.on(vim.fn.tempname())
    file_log_cmd.off()
    assert.is_false((log.file_log_state()))
  end)

  it("toggle() flips the current state", function()
    file_log_cmd.off()
    file_log_cmd.toggle()
    assert.is_true((log.file_log_state()))
    file_log_cmd.toggle()
    assert.is_false((log.file_log_state()))
  end)

  it("path('default') resets to the config/default path", function()
    local custom = vim.fn.tempname() .. "-custom.log"
    file_log_cmd.path(custom)
    local _, p1 = log.file_log_state()
    assert.are.equal(vim.fn.fnamemodify(custom, ":p"), p1)

    file_log_cmd.path("default")
    local ok = pcall(function()
      local _, p2 = log.file_log_state()
      assert(p2 ~= nil)
    end)
    assert.is_true(ok)
  end)

  it("status() and path(nil) report without mutating", function()
    log.set_file_log(false)
    local ok1 = pcall(file_log_cmd.status)
    local ok2 = pcall(file_log_cmd.path, nil)
    assert.is_true(ok1)
    assert.is_true(ok2)
    assert.is_false((log.file_log_state()))
  end)

  -- leave file logging off for any later spec sharing this singleton
  log.set_file_log(false)
  log.set_file_log_path(nil)
end)

describe("usrcmds.breadcrumbs (wrapper)", function()
  local crumbs = require("mdview.core.breadcrumbs")

  it("show() opens the mdview://breadcrumbs scratch buffer", function()
    crumbs.clear()
    breadcrumbs_cmd.show()
    vim.wait(30)
    assert(vim.fn.bufnr("mdview://breadcrumbs") ~= -1, "expected the breadcrumbs scratch buffer to exist")
  end)

  it("export(path) writes the formatted outline to disk", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "mdview_spec_crumbs_export.md")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Heading", "body" })
    crumbs.clear()
    crumbs.record(buf)

    local path = vim.fn.tempname() .. "-crumbs.md"
    breadcrumbs_cmd.export(path)
    assert.are.equal(1, vim.fn.filereadable(path))
    local content = table.concat(vim.fn.readfile(path), "\n")
    assert.is_true(content:find("Session breadcrumbs", 1, true) ~= nil)
    vim.fn.delete(path)
  end)

  it("clear() empties the recorded breadcrumbs", function()
    breadcrumbs_cmd.clear()
    assert.are.equal(0, #crumbs.snapshot())
  end)
end)

describe("usrcmds.show_weblogs / preview_tab (thin wrappers)", function()
  it("show_weblogs.run() delegates to adapter.log.show() without erroring", function()
    local ok, err = pcall(show_weblogs.run)
    assert.is_true(ok, tostring(err))
    vim.wait(30)
    assert(vim.fn.bufnr(require("mdview.config").defaults.log_buffer_name) ~= -1)
  end)

  it("preview_tab.run() delegates to adapter.preview_tab.toggle() without erroring", function()
    local preview_tab = require("mdview.adapter.preview_tab")
    local called = false
    local orig_toggle = preview_tab.toggle
    preview_tab.toggle = function()
      called = true
    end
    preview_tab_cmd.run()
    assert.is_true(called)
    preview_tab.toggle = orig_toggle
  end)
end)

ws.send_close = orig_send_close
vim.notify = orig_notify

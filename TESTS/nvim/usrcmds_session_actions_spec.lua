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

  it("reports an unwritable path as an error and opens nothing", function()
    -- A parent directory that does not exist: io.open fails, and before the
    -- fix the command still announced "diagnostics written to <path>" and
    -- opened an empty buffer for it.
    local path = vim.fn.tempname() .. "-no-such-dir/mdview-diagnose.txt"
    local tabs_before = vim.fn.tabpagenr("$")

    local report, err = require("mdview.diagnostics").run(path)
    assert.is_nil(report)
    assert.is_true(type(err) == "string" and err:find(path, 1, true) ~= nil)

    diagnose.run(path)
    assert.are.equal(0, vim.fn.filereadable(path))
    assert.are.equal(tabs_before, vim.fn.tabpagenr("$"))
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

  it("show() reuses the same buffer on a second call instead of a name collision", function()
    crumbs.clear()
    breadcrumbs_cmd.show()
    local first = vim.fn.bufnr("mdview://breadcrumbs")
    assert(first ~= -1, "expected the breadcrumbs scratch buffer to exist")
    -- Previously a bare pcall around nvim_buf_set_name swallowed the E95 name
    -- collision here and left the second buffer unnamed (LLS-31): asserting
    -- same bufnr *and* same name is what that regression would break.
    breadcrumbs_cmd.show()
    assert.are.equal(first, vim.fn.bufnr("mdview://breadcrumbs"))
    assert.are.equal("mdview://breadcrumbs", vim.api.nvim_buf_get_name(first))
  end)

  it("show() from another tab reuses the buffer instead of leaking an orphan", function()
    -- vim.fn.bufwinid() only searches the *current* tab page, so a naive
    -- reuse check misses a window showing the breadcrumbs buffer in some
    -- other tab: it takes the "not displayed" branch, opens a throwaway
    -- `botright new` window, and immediately discards that window's fresh
    -- scratch buffer by swapping in the existing one -- leaking one orphan
    -- buffer per invocation from a tab that doesn't already show it, and
    -- ending up with the breadcrumbs buffer displayed in two tabs at once.
    crumbs.clear()
    breadcrumbs_cmd.show() -- shows it in the current (first) tab
    local target = vim.fn.bufnr("mdview://breadcrumbs")

    vim.cmd("tabnew") -- tabnew itself adds its own blank buffer; count after it
    local bufs_before = #vim.api.nvim_list_bufs()
    breadcrumbs_cmd.show()

    assert.are.equal(bufs_before, #vim.api.nvim_list_bufs(), "no extra buffer should have leaked")
    assert.are.equal(target, vim.fn.bufnr("mdview://breadcrumbs"))

    local shown_in = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == target then
        shown_in = shown_in + 1
      end
    end
    assert.are.equal(1, shown_in, "the breadcrumbs buffer must not be shown in two tabs at once")

    vim.cmd("tabclose")
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

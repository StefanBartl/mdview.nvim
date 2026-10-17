---@module 'tests.nvim.shared_relay_spec'
-- The Neovim half of the shared relay (shared_relay.enabled): discovery,
-- ownership of the tab's room (only the owner pushes), the takeover on focus,
-- and leaving the relay running on :MDView stop. The relay half (routing of
-- write-backs to the owner, lifetime) is covered by native/server/shared_test.go;
-- the whole flow with two real instances is a live check (see the task notes).

---@diagnostic disable: undefined-global, duplicate-set-field

local shared = require("mdview.adapter.shared_relay")
local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local config = require("mdview.config")
local normalize = require("mdview.helper.normalize")

local ME = shared.client_id()

local function make_md_buffer(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# doc", "- [ ] task" })
  return buf
end

--- Run fn with vim.fn.jobstart recording the commands instead of running them.
---@param fn fun(started: string[][])
local function recording_jobs(fn)
  local orig = vim.fn.jobstart
  local started = {}
  vim.fn.jobstart = function(cmd, opts)
    started[#started + 1] = cmd
    if opts and opts.on_exit then
      opts.on_exit(1, 0, "exit")
    end
    return 1
  end
  local ok, err = pcall(fn, started)
  vim.fn.jobstart = orig
  if not ok then
    error(err, 0)
  end
end

---@param cmd string[]
---@return string|nil
local function url_of(cmd)
  for _, a in ipairs(cmd) do
    if type(a) == "string" and a:match("^http://") then
      return a
    end
  end
  return nil
end

local ROOM = "C:/notes/room.md"

local function attach_as_non_owner(tabs)
  shared.attach({ port = 43219, token = "tok", status = { tabs = tabs or { ROOM } } })
end

describe("shared_relay", function()
  local orig_enabled, orig_port

  before_each(function()
    orig_enabled = config.defaults.shared_relay.enabled
    orig_port = vim.g.mdview_server_port
    shared._reset()
  end)

  after_each(function()
    config.defaults.shared_relay.enabled = orig_enabled
    shared._reset()
    state.set_preview_key(nil)
    ws._ready = false
    vim.g.mdview_server_port = orig_port
  end)

  it("is off by default: no relay arguments, no client id, every push allowed", function()
    assert.is_false(require("mdview.config.DEFAULTS").shared_relay.enabled)
    config.defaults.shared_relay.enabled = false
    assert.are.same({}, shared.spawn_args())
    assert.are.equal("", shared.client_param())
    assert.is_true(shared.may_push())
  end)

  it("spawns the relay shared, with the discovery file and the idle timeout", function()
    config.defaults.shared_relay.enabled = true
    local args = shared.spawn_args()
    assert.are.equal("--shared", args[1])
    assert.are.equal(shared.discovery_path(), args[3])
    assert.are.same({ "--idle-timeout", tostring(config.defaults.shared_relay.idle_timeout_s) }, { args[4], args[5] })
  end)

  it("a non-owner pushes nothing into the tab; once it claims, its pushes name it", function()
    attach_as_non_owner()
    recording_jobs(function(started)
      ws.send_content(ROOM, { "# from a background instance" })
      ws.send_doc(ROOM, "C:/notes/other.md")
      ws.send_scroll(ROOM, 1, 2)
      assert.are.equal(0, #started, "a background instance must not steal the tab")

      shared.claim()
      ws.send_content(ROOM, { "# mine now" })
      assert.are.equal(1, #started)
      local url = url_of(started[1])
      assert.truthy(url and url:find("/update?", 1, true))
      assert.truthy(url:find("&client=" .. vim.uri_encode(ME), 1, true), url)
    end)
  end)

  it("stops pushing once the heartbeat says another instance owns the room", function()
    attach_as_non_owner()
    shared.claim()
    local before = vim.uv.now() - 1
    -- An answer to a request sent before the claim describes the old owner.
    shared.apply_status({ tabs = { ROOM }, owners = { [ROOM] = "nvim-other" } }, before)
    assert.is_true(shared.may_push())
    -- uv.now() is the loop's cached clock: a heartbeat stamped with the very
    -- tick of the claim may have left before it.
    shared.apply_status({ tabs = { ROOM }, owners = { [ROOM] = "nvim-other" } }, shared._claimed_at)
    assert.is_true(shared.may_push(), "an answer stamped with the claim's tick is not trusted")
    shared._claimed_at = 0
    shared.apply_status({ tabs = { ROOM }, owners = { [ROOM] = "nvim-other" } }, vim.uv.now())
    assert.is_false(shared.may_push())
    shared.apply_status({ tabs = { ROOM }, owners = { [ROOM] = ME } }, vim.uv.now())
    assert.is_true(shared.may_push())
  end)

  it("follows the tab that is open: its room becomes the preview key", function()
    attach_as_non_owner({})
    assert.is_nil(shared.tab_room())
    shared.apply_status({ tabs = { ROOM }, owners = {} }, vim.uv.now())
    assert.are.equal(ROOM, state.get_preview_key())
  end)

  it("takes the tab over with the current markdown buffer, not with any other buffer", function()
    local bs = require("mdview.bindings.autocmds.buffer_switch")
    local spot = require("mdview.bindings.autocmds.spotlight_sync")
    local orig_resync, orig_resend = bs.resync, spot.resend
    local resynced
    local resent = 0
    bs.resync = function(buf)
      resynced = buf
      return true
    end
    spot.resend = function()
      resent = resent + 1
    end
    local ok, err = pcall(function()
      attach_as_non_owner()
      local scratch = vim.api.nvim_create_buf(false, true)
      assert.is_false(shared.takeover(scratch))
      assert.is_false(shared.may_push(), "a buffer mdview does not preview claims nothing")
      assert.are.equal(0, resent)

      local md = make_md_buffer("mdview_shared_spec.md")
      require("mdview.bindings.autocmds.live_push")._last_doc[ROOM] = "C:/notes/stale.md"
      assert.is_true(shared.takeover(md))
      assert.are.equal(md, resynced)
      assert.is_true(shared.may_push())
      assert.are.equal(ROOM, state.get_preview_key())
      -- The document is named again, so the relay records the new owner.
      assert.is_nil(require("mdview.bindings.autocmds.live_push").shown_document(ROOM))
      assert.are.equal(1, resent, "the tab's spotlights become this instance's too")
    end)
    bs.resync, spot.resend = orig_resync, orig_resend
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= vim.api.nvim_get_current_buf() then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
    if not ok then
      error(err, 0)
    end
  end)

  it("takes over on focus always, on other activity only while another instance owns the tab", function()
    local orig_takeover = shared.takeover
    local calls = 0
    shared.takeover = function()
      calls = calls + 1
      return true
    end
    local group = vim.api.nvim_create_augroup("MdviewSharedSpec", { clear = true })
    local ok, err = pcall(function()
      attach_as_non_owner()
      shared.attach_autocmds(group)
      shared._owner = true
      vim.api.nvim_exec_autocmds("CursorMoved", { group = group })
      assert.are.equal(0, calls, "the owner does not resend on every cursor move")
      vim.api.nvim_exec_autocmds("FocusGained", { group = group })
      assert.are.equal(1, calls, "focus gained always takes the tab over")
      shared._owner = false
      vim.api.nvim_exec_autocmds("CursorMoved", { group = group })
      assert.are.equal(2, calls, "activity in a non-owner takes the tab over (no focus reporting)")
    end)
    shared.takeover = orig_takeover
    pcall(vim.api.nvim_del_augroup_by_id, group)
    if not ok then
      error(err, 0)
    end
  end)

  it("discovers a running shared relay and refuses anything else", function()
    local file = vim.fn.tempname() .. ".json"
    local orig_path, orig_probe = shared.discovery_path, shared._probe
    local answer
    shared.discovery_path = function()
      return file
    end
    shared._probe = function(url)
      assert.truthy(url:find("/attach?token=tok&client=", 1, true))
      return answer
    end
    local ok, err = pcall(function()
      assert.is_nil((shared.discover()))
      vim.fn.writefile({ "{ half a file" }, file)
      assert.is_nil((shared.discover()), "a broken discovery file is no relay")
      vim.fn.writefile({ vim.json.encode({ protocol = 1, port = 43300, token = "tok", pid = 1 }) }, file)

      answer = nil
      assert.is_nil((shared.discover()), "a relay that does not answer is a stale file")
      answer = vim.json.encode({ protocol = 1, shared = false, tabs = {} })
      assert.is_nil((shared.discover()), "an unshared relay is not attached to")
      answer = vim.json.encode({ protocol = 99, shared = true, tabs = {} })
      assert.is_nil((shared.discover()), "another protocol is not attached to")

      answer = vim.json.encode({ protocol = 1, shared = true, clients = 1, owners = {}, tabs = { ROOM } })
      local info = shared.discover()
      assert.are.equal(43300, info.port)
      assert.are.equal("tok", info.token)

      shared.attach(info)
      assert.are.equal("tok", state.get_token())
      assert.are.equal(43300, vim.g.mdview_server_port)
      assert.is_true(shared.is_attached())
      assert.is_false(shared.may_push(), "attached, but the tab is the other instance's until a takeover")
    end)
    shared.discovery_path, shared._probe = orig_path, orig_probe
    pcall(os.remove, file)
    if not ok then
      error(err, 0)
    end
  end)

  it(":MDView stop detaches and leaves the shared relay and its tab alone", function()
    local runner = require("mdview.adapter.runner")
    local orig_detach, orig_close, orig_stop = shared.detach, ws.send_close, runner.stop_server
    local detached, closed, killed = false, false, false
    shared.detach = function()
      detached = true
      shared._attached = false
    end
    ws.send_close = function()
      closed = true
    end
    runner.stop_server = function()
      killed = true
    end
    local ok, err = pcall(function()
      attach_as_non_owner()
      state.set_server(shared.handle())
      require("mdview.bindings.usrcmds.stop").stop(false)
      assert.is_true(detached)
      assert.is_false(closed, "the tab still serves the other instances")
      assert.is_false(killed, "the relay still serves the other instances")
      assert.is_nil(state.get_server())
    end)
    shared.detach, ws.send_close, runner.stop_server = orig_detach, orig_close, orig_stop
    state.set_server(nil)
    if not ok then
      error(err, 0)
    end
  end)

  it("without a shared relay the room key of a push carries no client", function()
    recording_jobs(function(started)
      ws.send_content(normalize.path("x.md") or "x.md", { "# x" })
      local url = url_of(started[1])
      assert.truthy(url and not url:find("client=", 1, true), url)
    end)
  end)
end)

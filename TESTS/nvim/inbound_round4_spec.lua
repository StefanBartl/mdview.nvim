---@module 'tests.nvim.inbound_round4_spec'
-- Review round 3, items 16 to 22 and 24: the browser -> buffer write-backs keep
-- their order per buffer, report what they cannot apply, reach the right room,
-- survive a CRLF last line, a lost document ping, a rename and a stop.

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")
local live = require("mdview.bindings.autocmds.live_push")
local ws = require("mdview.adapter.ws_client")
local control = require("mdview.adapter.control")
local state = require("mdview.core.state")
local display = require("mdview.core.display")
local config = require("mdview.config")
local bcfg = require("mdview.config.browser")

local function make_buf(name, lines)
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, name)
  vim.bo[b].filetype = "markdown"
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end

local shown = make_buf("mdview_spec_round4_shown.md", { "# Shown", "- [ ] one", '<input type="text" name="title">' })
vim.api.nvim_set_current_buf(shown)
local SHOWN = assert(normalize.path(vim.api.nvim_buf_get_name(shown)))
local ROOM = "mdview_spec_round4_room.md" -- the first document of the session: not a buffer

local function lines()
  return vim.api.nvim_buf_get_lines(shown, 0, -1, false)
end

local orig = {
  content = ws.send_content,
  doc = ws.send_doc,
  control = ws.send_control,
  ready = ws.wait_ready,
  ctl = control.send,
  mode = vim.api.nvim_get_mode,
  notify = vim.notify,
  active = display.active,
}
local sent, announced, notices, notes

local function typing(on)
  vim.api.nvim_get_mode = on and function()
    return { mode = "i", blocking = false }
  end or orig.mode
  inbound._set_last_key(on and vim.uv.now() or 0)
end

describe("inbound write-backs, round 4", function()
  before_each(function()
    inbound.stop()
    vim.bo[shown].modifiable = true
    vim.api.nvim_buf_set_lines(shown, 0, -1, false, { "# Shown", "- [ ] one", '<input type="text" name="title">' })
    live._last_doc = { [ROOM] = SHOWN }
    sent, announced, notices, notes = {}, {}, {}, {}
    ws.send_content = function(target)
      sent[#sent + 1] = target
    end
    ws.send_doc = function(key, path)
      announced[#announced + 1] = { key = key, path = path }
    end
    ws.send_control = function() end
    ws.wait_ready = function(cb)
      cb(true)
    end
    control.send = function(msg, key)
      notices[#notices + 1] = { msg = msg, key = key }
    end
    vim.notify = function(msg)
      notes[#notes + 1] = msg
    end
    state.set_preview_key(ROOM)
    bcfg.defaults.behavior = "reuse"
    config.defaults.edit_blocks = true
  end)

  after_each(function()
    inbound.stop()
    typing(false)
    live._last_doc = {}
    ws.send_content, ws.send_doc, ws.send_control, ws.wait_ready = orig.content, orig.doc, orig.control, orig.ready
    control.send = orig.ctl
    vim.notify = orig.notify
    display.active = orig.active
    state.set_preview_key(nil)
    config.defaults.edit_blocks = false
  end)

  it("16: a block edit of a CRLF buffer's last line matches an expected that ends in \\r", function()
    vim.api.nvim_buf_set_lines(shown, 0, -1, false, { "a\r", "b\r" })
    inbound._handle_edit(ROOM, 2, 2, "b\r", "c", SHOWN)
    assert.are.same({ "a\r", "c\r" }, lines())
  end)

  it("17: a later change does not overtake an earlier one that waits for the user to stop typing", function()
    typing(true)
    inbound._handle_field(ROOM, "title", "first", SHOWN)
    assert.are.equal('<input type="text" name="title">', lines()[3]) -- waiting
    typing(false)
    inbound._handle_field(ROOM, "title", "second", SHOWN)
    vim.wait(2000, function()
      return lines()[3]:find('value="second"', 1, true) ~= nil
    end, 20)
    assert.are.equal('<input type="text" name="title" value="second">', lines()[3])
  end)

  it("18: a write-back of an older room's tab also brings that tab up to date", function()
    state.set_preview_key("NEWROOM")
    inbound._handle_toggle(ROOM, 2, true, SHOWN)
    assert.are.equal("- [x] one", lines()[2])
    table.sort(sent)
    assert.are.same({ "NEWROOM", ROOM }, sent)
  end)

  it("19: a document ping the tab lost is sent again when its request names another document", function()
    inbound._handle_toggle(ROOM, 2, true, "some/other.md")
    assert.are.equal("- [ ] one", lines()[2])
    assert.are.same({ { key = ROOM, path = SHOWN } }, announced)
    assert.is_truthy(notices[1].msg.notice:find("try again", 1, true))
  end)

  it("20: a refused checkbox says why and puts the buffer's text back into the tab", function()
    inbound._handle_toggle(ROOM, 2, true, SHOWN, "- [ ] something else")
    assert.are.equal("- [ ] one", lines()[2])
    assert.is_truthy(notices[1].msg.notice:find("lines changed", 1, true))
    assert.is_true(#sent >= 1)
    sent = {}
    notices = {}
    inbound._handle_toggle(ROOM, 3, true, SHOWN) -- not a checkbox line
    assert.is_truthy(notices[1].msg.notice:find("no longer a checkbox", 1, true))
    assert.is_true(#sent >= 1)
  end)

  it("20: a field that no longer exists is refused with a notice", function()
    inbound._handle_field(ROOM, "gone", "x", SHOWN)
    assert.is_truthy(notices[1].msg.notice:find("no text field named gone", 1, true))
  end)

  it("21: renaming the shown buffer announces its new path", function()
    local group = vim.api.nvim_create_augroup("MdviewSpecRound4", { clear = true })
    live.attach(group)
    local old = vim.api.nvim_buf_get_name(shown)
    local new = vim.fn.fnamemodify(old, ":h") .. "/mdview_spec_round4_renamed.md"
    vim.api.nvim_buf_set_name(shown, new)
    vim.api.nvim_exec_autocmds("BufFilePost", { buffer = shown })
    local NEW = normalize.path(new)
    assert.are.equal(NEW, live.shown_document(ROOM))
    vim.api.nvim_buf_set_name(shown, old)
    vim.api.nvim_del_augroup_by_id(group)
    live._cancel_pending()
  end)

  it("22: reverse scroll and navigation use the document on screen, not the room", function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    inbound._handle_scroll(ROOM, 1)
    assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("24: a stop drops changes that were still waiting", function()
    typing(true)
    inbound._handle_field(ROOM, "title", "late", SHOWN)
    inbound.stop()
    typing(false)
    vim.wait(700, function()
      return false
    end, 50)
    assert.are.equal('<input type="text" name="title">', lines()[3])
  end)

  it("24: an error inside a queued change is reported, and the next change still runs", function()
    local calls = 0
    display.active = function()
      calls = calls + 1
      if calls == 1 then
        error("boom")
      end
      return false
    end
    inbound._handle_toggle(ROOM, 2, true, SHOWN, "- [ ] one")
    local found = false
    for _, n in ipairs(notes) do
      if n:find("boom", 1, true) then
        found = true
      end
    end
    assert.is_true(found)
    inbound._handle_toggle(ROOM, 2, true, SHOWN, "- [ ] one")
    assert.are.equal("- [x] one", lines()[2])
  end)
end)

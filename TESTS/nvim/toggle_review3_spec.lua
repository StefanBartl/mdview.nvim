---@module 'tests.nvim.toggle_review3_spec'
-- Review round 3, items 1 to 3: a toggle under a display language, a tick and
-- an immediate untick against the same rendered text, and an edit that arrives
-- while the user stands in insert mode.

---@diagnostic disable: undefined-global

local inbound = require("mdview.adapter.inbound_poll")
local normalize = require("mdview.helper.normalize")
local display = require("mdview.core.display")
local live = require("mdview.bindings.autocmds.live_push")
local ws = require("mdview.adapter.ws_client")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "mdview_spec_toggle_review3.md")
vim.bo[buf].filetype = "markdown"
vim.api.nvim_set_current_buf(buf)
local KEY = assert(normalize.path(vim.api.nvim_buf_get_name(buf)))

local ws_orig = { content = ws.send_content, doc = ws.send_doc, control = ws.send_control }
local active_orig = display.active

local function lines()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

describe("toggle, review round 3", function()
  before_each(function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Aufgaben", "- [ ] erste" })
    live._last_doc[KEY] = KEY
    ws.send_content = function() end
    ws.send_doc = function() end
    ws.send_control = function() end
  end)
  after_each(function()
    live._last_doc[KEY] = nil
    display.active = active_orig
    ws.send_content, ws.send_doc, ws.send_control = ws_orig.content, ws_orig.doc, ws_orig.control
  end)

  it("under a display language the translated `expected` does not drop the tick", function()
    display.active = function()
      return true
    end
    inbound._handle_toggle(KEY, 2, true, KEY, "- [ ] first")
    assert.are.same({ "# Aufgaben", "- [x] erste" }, lines())
  end)

  it("without a display language a different `expected` still drops the tick", function()
    display.active = function()
      return false
    end
    inbound._handle_toggle(KEY, 2, true, KEY, "- [ ] first")
    assert.are.same({ "# Aufgaben", "- [ ] erste" }, lines())
  end)

  it("tick and an immediate untick (double click) both apply", function()
    inbound._handle_toggle(KEY, 2, true, KEY, "- [ ] erste")
    inbound._handle_toggle(KEY, 2, false, KEY, "- [ ] erste") -- still the original text
    assert.are.same({ "# Aufgaben", "- [ ] erste" }, lines())
  end)

  it("[x] and [X] in `expected` match either marker", function()
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "- [X] erste" })
    inbound._handle_toggle(KEY, 2, false, KEY, "- [x] erste")
    assert.are.same({ "# Aufgaben", "- [ ] erste" }, lines())
  end)
end)

describe("when_not_inserting, review round 3", function()
  local mode_orig = vim.api.nvim_get_mode
  local notes
  local notify_orig = vim.notify
  before_each(function()
    notes = {}
    vim.notify = function(msg)
      notes[#notes + 1] = msg
    end
  end)
  after_each(function()
    vim.api.nvim_get_mode = mode_orig
    vim.notify = notify_orig
  end)

  local function in_insert()
    vim.api.nvim_get_mode = function()
      return { mode = "i", blocking = false }
    end
  end

  it("applies at once when only standing in insert mode (no recent key)", function()
    in_insert()
    inbound._set_last_key(0)
    local ran = 0
    inbound._when_not_inserting(buf, function()
      ran = ran + 1
    end)
    assert.are.equal(1, ran)
    assert.are.same({}, notes)
  end)

  it("waits while keys are being typed, and says so once", function()
    in_insert()
    inbound._set_last_key(vim.uv.now())
    local ran = 0
    inbound._when_not_inserting(buf, function()
      ran = ran + 1
    end)
    assert.are.equal(0, ran)
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find("stop typing", 1, true))
    -- the user stops: the deferred retry applies it
    inbound._set_last_key(0)
    vim.wait(1000, function()
      return ran > 0
    end, 20)
    assert.are.equal(1, ran)
    assert.are.equal(1, #notes)
  end)

  it("runs at once outside insert mode", function()
    local ran = 0
    inbound._set_last_key(vim.uv.now())
    inbound._when_not_inserting(buf, function()
      ran = ran + 1
    end)
    assert.are.equal(1, ran)
  end)
end)

---@module 'tests.nvim.spotlight_sync_spec'
-- Covers the Neovim half of the spotlight mirror end to end, up to the transport:
-- the `User SpotlightChanged` autocmd (and the colorscheme triggers) in, the
-- payload handed to ws_client.send_spotlight out. spotlight.nvim and the relay
-- are stubs; everything between them is the real module.
--
-- The browser half -- turning the payload into highlights -- is covered in
-- TESTS/client/spotlightMirror.test.ts.

---@diagnostic disable: undefined-global, need-check-nil, duplicate-set-field

local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local sync = require("mdview.bindings.autocmds.spotlight_sync")
local spotlight_cmd = require("mdview.bindings.usrcmds.spotlight")
local cfg = require("mdview.config")

local original_plugin = package.loaded["spotlight"]
local original_wait_ready = ws.wait_ready
local original_send = ws.send_spotlight

-- What the stubbed spotlight.nvim currently holds.
local items, palette
-- What reached the (stubbed) relay, decoded; and the callbacks of in-flight sends.
local sent, pending
-- true: the relay answers at once; false: the test completes each send itself.
local auto_ack
local ack_ok, ack_err

local function install_plugin()
  package.loaded["spotlight"] = {
    spotlights = function()
      return vim.deepcopy(items)
    end,
    colors = function()
      return vim.deepcopy(palette)
    end,
  }
end

local function fire(data)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "SpotlightChanged",
    modeline = false,
    data = data or { reasons = { "add" }, count = #items, whole_file_count = #items, whole_file_changed = true },
  })
end

--- Wait until `n` payloads arrived (or fail after a second).
local function wait_for(n)
  vim.wait(1000, function()
    return #sent >= n
  end, 5)
  assert.are.equal(n, #sent)
end

--- Wait long enough for a debounced send to have happened, if one was coming.
local function settle()
  vim.wait(sync.DEBOUNCE_MS * 6, function()
    return false
  end, 5)
end

describe("spotlight_sync", function()
  local group

  before_each(function()
    items = { { text = "SYSsystosca", slot = 1, line_mode = false, kind = "word", ignore_case = false } }
    palette = { { slot = 1, group = "Spotlight1", fg = "#000000", bg = "#ffee00", bold = false } }
    sent, pending = {}, {}
    auto_ack, ack_ok, ack_err = true, true, nil
    install_plugin()

    sync.DEBOUNCE_MS = 15
    cfg.defaults.browser.spotlight_sync = true
    cfg.defaults.browser.spotlight_max_matches = 500
    state.set_server({ stub = true })

    ws.wait_ready = function(cb)
      cb(true)
    end
    ws.send_spotlight = function(json, cb)
      sent[#sent + 1] = vim.json.decode(json)
      if auto_ack then
        cb(ack_ok, ack_err)
      else
        pending[#pending + 1] = cb
      end
    end

    group = vim.api.nvim_create_augroup("MdviewSpotlightSyncSpec", { clear = true })
  end)

  after_each(function()
    sync.reset()
    pcall(vim.api.nvim_del_augroup_by_id, group)
    state.clear_server()
    ws.wait_ready = original_wait_ready
    ws.send_spotlight = original_send
    package.loaded["spotlight"] = original_plugin
  end)

  it("sends the current spotlights when a session attaches", function()
    sync.attach(group)
    wait_for(1)
    assert.are.equal("spotlight", sent[1].type)
    assert.are.equal("SYSsystosca", sent[1].items[1].text)
    assert.are.equal("#ffee00", sent[1].colors[1].bg)
    assert.are.equal(500, sent[1].max)
  end)

  it("sends nothing at attach when nothing is marked (the relay starts empty)", function()
    items = {}
    sync.attach(group)
    settle()
    assert.are.equal(0, #sent)
  end)

  it("coalesces a burst of events into one send", function()
    items = {}
    sync.attach(group)
    items = { { text = "a", slot = 1 }, { text = "b", slot = 2 } }
    fire()
    fire()
    fire()
    wait_for(1)
    settle()
    assert.are.equal(1, #sent)
    assert.are.equal(2, #sent[1].items)
  end)

  it("does not send a state the relay already has", function()
    sync.attach(group)
    wait_for(1)
    fire()
    vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
    settle()
    assert.are.equal(1, #sent)
  end)

  it("ignores a change that only concerned 'this occurrence only' spotlights", function()
    sync.attach(group)
    wait_for(1)
    items[#items + 1] = { text = "buffer-only", slot = 2 } -- the stub would report it if asked
    fire({ reasons = { "add" }, count = 2, whole_file_count = 1, whole_file_changed = false })
    settle()
    assert.are.equal(1, #sent)
  end)

  it("syncs on an event without a payload (an older spotlight.nvim)", function()
    items = {}
    sync.attach(group)
    items = { { text = "x", slot = 1 } }
    vim.api.nvim_exec_autocmds("User", { pattern = "SpotlightChanged", modeline = false })
    wait_for(1)
  end)

  it("re-sends the palette after a colorscheme change", function()
    sync.attach(group)
    wait_for(1)
    palette[1].bg = "#00ff00"
    vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
    wait_for(2)
    assert.are.equal("#00ff00", sent[2].colors[1].bg)
  end)

  it("re-sends the palette after 'background' changed", function()
    sync.attach(group)
    wait_for(1)
    palette[1].bg = "#123456"
    vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background", modeline = false })
    wait_for(2)
    assert.are.equal("#123456", sent[2].colors[1].bg)
  end)

  it("tells the preview when the last spotlight is gone", function()
    sync.attach(group)
    wait_for(1)
    items = {}
    fire({ reasons = { "clear" }, count = 0, whole_file_count = 0, whole_file_changed = true })
    wait_for(2)
    assert.are.same({}, sent[2].items)
  end)

  it("does nothing with browser.spotlight_sync = false", function()
    cfg.defaults.browser.spotlight_sync = false
    sync.attach(group)
    fire()
    vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
    settle()
    assert.are.equal(0, #sent)
  end)

  it("clears the preview when the option is switched off mid-session", function()
    sync.attach(group)
    wait_for(1)
    cfg.defaults.browser.spotlight_sync = false
    sync.sync_now()
    wait_for(2)
    assert.are.same({}, sent[2].items)
    -- and stays quiet afterwards: nothing more to clear
    fire()
    settle()
    assert.are.equal(2, #sent)
  end)

  it("is a quiet no-op without spotlight.nvim", function()
    package.loaded["spotlight"] = nil
    package.preload["spotlight"] = function()
      error("module 'spotlight' not found")
    end
    sync.attach(group)
    fire()
    vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
    settle()
    assert.are.equal(0, #sent)
    package.preload["spotlight"] = nil
  end)

  it("sends nothing while no session is running", function()
    state.clear_server()
    sync.attach(group)
    fire()
    settle()
    assert.are.equal(0, #sent)
  end)

  it("tries again after the relay refused a state, instead of recording it as sent", function()
    ack_ok, ack_err = false, "404 page not found"
    sync.attach(group)
    wait_for(1)
    ack_ok, ack_err = true, nil
    fire()
    wait_for(2) -- the same state is sent again: the first one never arrived
    fire()
    settle()
    assert.are.equal(2, #sent) -- ...and now it is recorded
  end)

  it("forgets what it sent when the session is reset", function()
    sync.attach(group)
    wait_for(1)
    sync.reset()
    sync.attach(group)
    wait_for(2) -- a new relay starts empty, so the same state goes out again
  end)

  it("never lets a second POST overtake one that is still in flight", function()
    auto_ack = false
    items = {}
    sync.attach(group)
    items = { { text = "first", slot = 1 } }
    fire()
    wait_for(1)

    items = { { text = "second", slot = 1 } }
    fire()
    settle()
    assert.are.equal(1, #sent) -- held back while the first is on its way

    pending[1](true) -- the relay answers
    wait_for(2)
    assert.are.equal("second", sent[2].items[1].text)
  end)

  describe(":MDView spotlight", function()
    it("switches the option and re-reads the spotlights right away", function()
      cfg.defaults.browser.spotlight_sync = false
      sync.attach(group)
      spotlight_cmd.run("on")
      assert.is_true(cfg.defaults.browser.spotlight_sync)
      wait_for(1)

      spotlight_cmd.run("off")
      assert.is_false(cfg.defaults.browser.spotlight_sync)
      wait_for(2)
      assert.are.same({}, sent[2].items)
    end)

    it("toggles with no argument and refuses an unknown one", function()
      spotlight_cmd.run(nil)
      assert.is_false(cfg.defaults.browser.spotlight_sync)
      spotlight_cmd.run("toggle")
      assert.is_true(cfg.defaults.browser.spotlight_sync)
      spotlight_cmd.run("sideways")
      assert.is_true(cfg.defaults.browser.spotlight_sync) -- unchanged
    end)
  end)
end)

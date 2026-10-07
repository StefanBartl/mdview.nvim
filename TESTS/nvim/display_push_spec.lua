---@module 'tests.nvim.display_push_spec'
-- The display transform on the real push paths: live_push, buffer_switch,
-- try_push, and the pieces around them (`:MDView lang`, standalone, the reverse
-- paths, :checkhealth). language.nvim is a scripted fake, the transport is
-- stubbed: nothing here touches the network or a relay.

---@diagnostic disable: undefined-global, duplicate-set-field

local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local session = require("mdview.core.session")
local display = require("mdview.core.display")
local config = require("mdview.config")
local live = require("mdview.bindings.autocmds.live_push")
local buffer_switch = require("mdview.bindings.autocmds.buffer_switch")
local normalize = require("mdview.helper.normalize")

local saved = {}
local sent, docs, runs, notes

--- Replace what a spec touches; `restore` puts it back.
local function install()
  saved = {
    send_content = ws.send_content,
    send_doc = ws.send_doc,
    wait_ready = ws.wait_ready,
    send_control = ws.send_control,
    notify = vim.notify,
    language = package.loaded["language"],
    lang_config = package.loaded["language.config"],
    registry = package.loaded["language.translate.providers.registry"],
    get_server = state.get_server,
    preview_key = state.get_preview_key(),
    browser = vim.deepcopy(config.defaults.browser),
  }
  sent, docs, runs, notes = {}, {}, {}, {}
  ws.send_content = function(target, lines, opts)
    sent[#sent + 1] = { target = target, lines = vim.deepcopy(lines), full = opts and opts.full }
  end
  ws.send_doc = function(target, path)
    docs[#docs + 1] = { target = target, path = path }
  end
  ws.send_control = function() end
  ws.wait_ready = function(cb)
    cb(true)
  end
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = msg, level = level }
  end
  package.loaded["language"] = {
    translate_markdown = function(lines, opts, cb)
      local run = { lines = lines, opts = opts, cb = cb }
      runs[#runs + 1] = run
      local handle = {
        cancel = function()
          if not run.done then
            run.done = true
            cb(false, "cancelled")
          end
        end,
      }
      if opts.cache_only then
        vim.schedule(function()
          if not run.done then
            run.done = true
            cb(true, vim.list_slice(lines), { pending = #lines })
          end
        end)
      end
      return handle
    end,
  }
  package.loaded["language.config"] = {
    get = function()
      return { translate = { engine = "fakeengine" } }
    end,
  }
  package.loaded["language.translate.providers.registry"] = {
    resolve = function()
      return { name = "fakeengine" }, nil
    end,
  }
  local b = config.defaults.browser
  b.display_lang, b.transform, b.display_lang_trigger, b.display_lang_debounce_ms = nil, nil, "idle", 20
  display.reset()
  live._last_doc = {}
end

local function restore()
  display.reset()
  ws.send_content, ws.send_doc, ws.wait_ready, ws.send_control =
    saved.send_content, saved.send_doc, saved.wait_ready, saved.send_control
  vim.notify = saved.notify
  package.loaded["language"] = saved.language
  package.loaded["language.config"] = saved.lang_config
  package.loaded["language.translate.providers.registry"] = saved.registry
  state.get_server = saved.get_server
  state.set_preview_key(saved.preview_key)
  local b = config.defaults.browser
  for _, k in ipairs({ "display_lang", "transform", "display_lang_trigger", "display_lang_debounce_ms" }) do
    b[k] = saved.browser[k]
  end
end

---@param name string
---@param lines string[]
---@return integer buf
local function make_buf(name, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function settle(cond)
  return vim.wait(500, cond, 5)
end

local function full_runs()
  local r = {}
  for _, run in ipairs(runs) do
    if not run.opts.cache_only then
      r[#r + 1] = run
    end
  end
  return r
end

describe("live_push with a display language", function()
  local buf
  before_each(function()
    install()
    buf = make_buf("mdview_spec_display_live.md", { "# Titel", "Text" })
    session.init()
  end)
  after_each(function()
    restore()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("without the option a push is one synchronous send of the buffer text", function()
    live.push_buffer_changes(buf)
    assert.are.equal(1, #sent)
    assert.are.same({ "# Titel", "Text" }, sent[1].lines)
    assert.are.equal(1, #docs)
    assert.are.equal(0, #runs, "language.nvim is not touched")
  end)

  it("sends the valid text at once, the translation last, and keeps the buffer and snapshot original", function()
    config.defaults.browser.display_lang = "en"
    live.push_buffer_changes(buf, { full = true, reason = "save" })
    assert.is_true(settle(function()
      return #full_runs() == 1
    end))
    assert.are.same({ "# Titel", "Text" }, sent[1].lines, "first paint: cache-only, here the original")
    assert.are.equal(1, #docs, "the document is announced once")

    full_runs()[1].cb(true, { "# Title", "Text" }, { failed = 0 })
    assert.is_true(settle(function()
      return #sent >= 2
    end))
    assert.are.same({ "# Title", "Text" }, sent[#sent].lines)
    assert.are.equal(1, #docs, "a later text of the same document does not announce it again")
    for _, s in ipairs(sent) do
      assert.are.equal(2, #s.lines)
    end
    assert.are.same({ "# Titel", "Text" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false), "the buffer is untouched")
    local entry = session.get(normalize.path(vim.api.nvim_buf_get_name(buf)))
    assert.are.same({ "# Titel", "Text" }, entry.lines, "the snapshot is the original")
  end)

  it("a translation that arrives after the buffer was wiped sends nothing", function()
    config.defaults.browser.display_lang = "en"
    live.push_buffer_changes(buf, { full = true, reason = "save" })
    assert.is_true(settle(function()
      return #full_runs() == 1
    end))
    local before = #sent
    vim.api.nvim_buf_delete(buf, { force = true })
    full_runs()[1].cb(true, { "# Title", "Text" }, { failed = 0 })
    vim.wait(100, function()
      return false
    end, 10)
    assert.are.equal(before, #sent)
  end)
end)

describe("buffer_switch.resync with a display language (reuse mode, one shared room)", function()
  local a, b
  before_each(function()
    install()
    a = make_buf("mdview_spec_display_A.md", { "a-eins", "a-zwei" })
    b = make_buf("mdview_spec_display_B.md", { "b-eins", "b-zwei" })
    state.set_preview_key("the/one/preview/room")
    config.defaults.browser.display_lang = "en"
  end)
  after_each(function()
    restore()
    pcall(vim.api.nvim_buf_delete, a, { force = true })
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end)

  it("never sends document A's translation after the switch to B", function()
    assert.is_true(buffer_switch.resync(a))
    assert.is_true(settle(function()
      return #full_runs() == 1
    end))
    local a_run = full_runs()[1]

    assert.is_true(buffer_switch.resync(b))
    assert.is_true(settle(function()
      return #full_runs() == 2
    end))
    a_run.cb(true, { "A-ONE", "A-TWO" }, { failed = 0 }) -- the abandoned run answers late
    full_runs()[2].cb(true, { "B-ONE", "B-TWO" }, { failed = 0 })
    assert.is_true(settle(function()
      return sent[#sent] and sent[#sent].lines[1] == "B-ONE"
    end))
    for _, s in ipairs(sent) do
      assert.are_not.same({ "A-ONE", "A-TWO" }, s.lines)
      assert.are.equal("the/one/preview/room", s.target)
      assert.are.equal(2, #s.lines)
    end
    assert.is_true(sent[1].full, "a switch seeds the room with a full snapshot")
  end)
end)

describe("try_push with a display language", function()
  after_each(restore)

  it("seeds the room with the valid text and then the translation", function()
    install()
    config.defaults.browser.display_lang = "en"
    local try_push = require("mdview.bindings.usrcmds.start.server.try_push")
    try_push.try_push("/x/doc.md", { "Hallo" }, { max_attempts = 1, initial_delay_ms = 0, jitter = false })
    assert.is_true(settle(function()
      return #full_runs() == 1
    end))
    assert.are.same({ "Hallo" }, sent[1].lines)
    assert.is_true(sent[1].full)
    full_runs()[1].cb(true, { "Hello" }, { failed = 0 })
    assert.is_true(settle(function()
      return #sent >= 2
    end))
    assert.are.same({ "Hello" }, sent[#sent].lines)
  end)
end)

describe(":MDView lang", function()
  local lang = require("mdview.bindings.usrcmds.lang")
  local buf
  before_each(function()
    install()
    buf = make_buf("mdview_spec_display_cmd.md", { "# Titel" })
    vim.api.nvim_set_current_buf(buf)
    state.get_server = function()
      return { running = true }
    end
    state.set_preview_key(nil)
    session.init()
  end)
  after_each(function()
    restore()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("reports the state without changing anything", function()
    lang.run(nil)
    assert.is_nil(config.defaults.browser.display_lang)
    assert.is_truthy(notes[#notes].msg:find("off", 1, true))
    config.defaults.browser.display_lang = "en"
    lang.run("")
    assert.is_truthy(notes[#notes].msg:find("en", 1, true))
    assert.is_truthy(notes[#notes].msg:find("fakeengine", 1, true))
  end)

  it("<code> switches on and re-pushes; off restores the original at once and synchronously", function()
    lang.run("en")
    assert.are.equal("en", config.defaults.browser.display_lang)
    assert.is_true(settle(function()
      return #full_runs() == 1
    end))
    local n = #sent
    lang.run("off")
    assert.is_nil(config.defaults.browser.display_lang)
    assert.are.equal(n + 1, #sent, "the original went out synchronously")
    assert.are.same({ "# Titel" }, sent[#sent].lines)
    assert.is_true(full_runs()[1].done, "the run in flight was cancelled")
  end)

  it("rejects a malformed code and refresh without a language", function()
    lang.run("e n!")
    assert.is_nil(config.defaults.browser.display_lang)
    assert.are.equal(vim.log.levels.WARN, notes[#notes].level)
    lang.run("refresh")
    assert.is_truthy(notes[#notes].msg:find("off", 1, true))
  end)

  it("has completion candidates including off and refresh", function()
    assert.is_true(vim.tbl_contains(lang.values, "off"))
    assert.is_true(vim.tbl_contains(lang.values, "refresh"))
    assert.is_true(vim.tbl_contains(lang.values, "en"))
  end)
end)

describe("standalone mode and the display transform", function()
  before_each(install)
  after_each(restore)

  it("refuses with a clear message while a display language is set", function()
    config.defaults.browser.display_lang = "en"
    require("mdview.bindings.usrcmds.standalone").run(nil, true)
    assert.are.equal(vim.log.levels.ERROR, notes[#notes].level)
    assert.is_truthy(notes[#notes].msg:find("does not support", 1, true))
    assert.is_truthy(notes[#notes].msg:find("lang off", 1, true))
  end)
end)

describe("reverse paths while the preview shows a transformed text", function()
  local inbound = require("mdview.adapter.inbound_poll")
  local buf, key
  before_each(function()
    install()
    buf = make_buf("mdview_spec_display_reverse.md", {
      "# Aufgaben",
      "- [ ] erste",
      '<input type="text" name="title">',
    })
    vim.api.nvim_set_current_buf(buf)
    key = normalize.path(vim.api.nvim_buf_get_name(buf))
    config.defaults.browser.display_lang = "en"
  end)
  after_each(function()
    restore()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("text-field sync is off: the buffer is not written, said once", function()
    inbound._handle_field(key, "title", "Hello")
    inbound._handle_field(key, "title", "Hello again")
    assert.are.equal('<input type="text" name="title">', vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1])
    local said = 0
    for _, n in ipairs(notes) do
      if n.msg:find("text-field sync is off", 1, true) then
        said = said + 1
      end
    end
    assert.are.equal(1, said)
  end)

  it("text-field sync works when nothing is transformed", function()
    config.defaults.browser.display_lang = nil
    inbound._handle_field(key, "title", "Hello")
    assert.are.equal('<input type="text" name="title" value="Hello">', vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1])
  end)

  it("a checkbox toggle still writes only the marker into the real line", function()
    inbound._handle_toggle(key, 2, true)
    assert.are.same(
      { "# Aufgaben", "- [x] erste", '<input type="text" name="title">' },
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    )
  end)
end)

describe("config validation and :checkhealth", function()
  before_each(install)
  after_each(restore)

  it("setup reports a malformed option once and keeps the display off", function()
    require("mdview.config").merge({ browser = { display_lang = "no way!" } })
    assert.is_nil(display.lang())
    local said = 0
    for _, n in ipairs(notes) do
      if n.msg:find("display_lang must be a language code", 1, true) then
        said = said + 1
      end
    end
    assert.are.equal(1, said)
  end)

  it("known keys are not flagged as unknown", function()
    require("mdview.config").validate({
      browser = {
        display_lang = "en",
        display_lang_trigger = "save",
        display_lang_debounce_ms = 500,
        transform = function() end,
      },
    })
    assert.are.equal(0, #notes, "no warning for the new keys")
  end)

  it("engine_info names the engine and health completes with and without language.nvim", function()
    config.defaults.browser.display_lang = "en"
    local info = display.engine_info()
    assert.is_true(info.found)
    assert.is_true(info.available)
    assert.are.equal("fakeengine", info.engine)
    assert.is_true(pcall(require("mdview.health").check))

    package.loaded["language"] = nil
    package.preload["language"] = function()
      error("module 'language' not found")
    end
    local missing = display.engine_info()
    assert.is_false(missing.found)
    assert.is_true(pcall(require("mdview.health").check))
    package.preload["language"] = nil
  end)
end)

describe("the first text of a display transform arrives after the push call returned", function()
  local a
  before_each(function()
    install()
    a = make_buf("mdview_spec_display_first.md", { "eins", "zwei" })
    config.defaults.browser.display_lang = "en"
  end)
  after_each(function()
    restore()
    pcall(vim.api.nvim_buf_delete, a, { force = true })
  end)

  it("live_push: a buffer wiped before even the cache-only text arrived sends nothing", function()
    live.push_buffer_changes(a, { full = true, reason = "save" })
    vim.api.nvim_buf_delete(a, { force = true })
    vim.wait(100, function()
      return false
    end, 10)
    assert.are.equal(0, #sent)
    assert.are.equal(0, #docs)
  end)

  it("buffer_switch: a buffer wiped before the first text arrived sends nothing", function()
    state.set_preview_key("the/one/preview/room")
    assert.is_true(buffer_switch.resync(a))
    vim.api.nvim_buf_delete(a, { force = true })
    vim.wait(100, function()
      return false
    end, 10)
    assert.are.equal(0, #sent)
  end)
end)

describe(":MDView lang off restores the document the tab shows, not only the current buffer", function()
  local lang = require("mdview.bindings.usrcmds.lang")
  local bcfg = require("mdview.config.browser")
  local a, b, scratch, behavior
  before_each(function()
    install()
    behavior = bcfg.defaults.behavior
    a = make_buf("mdview_spec_display_offA.md", { "a-eins" })
    b = make_buf("mdview_spec_display_offB.md", { "b-eins" })
    scratch = vim.api.nvim_create_buf(false, true) -- a scratch buffer: not previewable
    state.get_server = function()
      return { running = true }
    end
    state.set_preview_key(nil)
    session.init()
    config.defaults.browser.display_lang = "en"
  end)
  after_each(function()
    bcfg.defaults.behavior = behavior
    restore()
    for _, buf in ipairs({ a, b, scratch }) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)

  it("reuse: focus in a scratch buffer, the tab still shows document A", function()
    bcfg.defaults.behavior = "reuse"
    live.push_buffer_changes(a, { full = true, reason = "save" })
    assert.is_true(settle(function()
      return #full_runs() == 1
    end))
    full_runs()[1].cb(true, { "A-EINS" }, { failed = 0 })
    assert.is_true(settle(function()
      return sent[#sent].lines[1] == "A-EINS"
    end))
    vim.api.nvim_set_current_buf(scratch)
    local n = #sent
    lang.run("off")
    assert.are.equal(n + 1, #sent, "the original of A went out")
    assert.are.same({ "a-eins" }, sent[#sent].lines)
  end)

  it("one room per document: every shown document is restored", function()
    bcfg.defaults.behavior = "new_tab"
    live.push_buffer_changes(a, { full = true, reason = "save" })
    live.push_buffer_changes(b, { full = true, reason = "save" })
    assert.is_true(settle(function()
      return #full_runs() == 2
    end))
    vim.api.nvim_set_current_buf(scratch)
    local n = #sent
    lang.run("off")
    local originals = {}
    for i = n + 1, #sent do
      originals[#originals + 1] = sent[i].lines[1]
    end
    table.sort(originals)
    assert.are.same({ "a-eins", "b-eins" }, originals)
  end)
end)

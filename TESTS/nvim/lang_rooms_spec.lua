---@module 'tests.nvim.lang_rooms_spec'
-- Tabs of other display languages (`core/lang_rooms.lua`): the buffer stays in its language, the tab of the preview
-- shows it as it is, and each `:MDView lang open <code>` tab shows the same document in <code>, following every
-- buffer the preview follows. language.nvim is a scripted fake and the transport is stubbed: nothing here touches
-- the network or a relay.

---@diagnostic disable: undefined-global, duplicate-set-field

local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local display = require("mdview.core.display")
local config = require("mdview.config")
local live = require("mdview.bindings.autocmds.live_push")
local buffer_switch = require("mdview.bindings.autocmds.buffer_switch")
local rooms = require("mdview.core.lang_rooms")

local MAIN = "the/one/preview/room"

local saved = {}
local sent, runs, controls, posts

local function install()
  saved = {
    send_content = ws.send_content,
    send_doc = ws.send_doc,
    wait_ready = ws.wait_ready,
    send_control = ws.send_control,
    jobstart = vim.fn.jobstart,
    notify = vim.notify,
    language = package.loaded["language"],
    lang_config = package.loaded["language.config"],
    registry = package.loaded["language.translate.providers.registry"],
    get_server = state.get_server,
    preview_key = state.get_preview_key(),
    browser = vim.deepcopy(config.defaults.browser),
  }
  sent, runs, controls, posts = {}, {}, {}, {}
  ws.send_content = function(target, lines, opts)
    sent[#sent + 1] = { target = target, lines = vim.deepcopy(lines), full = opts and opts.full }
  end
  ws.send_doc = function() end
  ws.send_control = function(key, json)
    controls[#controls + 1] = { key = key, json = json }
  end
  ws.wait_ready = function(cb)
    cb(true)
  end
  vim.fn.jobstart = function(cmd)
    posts[#posts + 1] = cmd
    return 1
  end
  vim.notify = function() end
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
  b.behavior = "reuse"
  display.reset()
  rooms.reset()
  live._last_doc = {}
  state.set_preview_key(MAIN)
end

local function restore()
  display.reset()
  rooms.reset()
  ws.send_content, ws.send_doc, ws.wait_ready, ws.send_control =
    saved.send_content, saved.send_doc, saved.wait_ready, saved.send_control
  vim.fn.jobstart = saved.jobstart
  vim.notify = saved.notify
  package.loaded["language"] = saved.language
  package.loaded["language.config"] = saved.lang_config
  package.loaded["language.translate.providers.registry"] = saved.registry
  state.get_server = saved.get_server
  state.set_preview_key(saved.preview_key)
  local b = config.defaults.browser
  for _, k in ipairs({ "display_lang", "transform", "display_lang_trigger", "display_lang_debounce_ms", "behavior" }) do
    b[k] = saved.browser[k]
  end
end

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

--- The full (not cache-only) runs, by the language they translate to.
local function full_runs(lang)
  local r = {}
  for _, run in ipairs(runs) do
    if not run.opts.cache_only and (lang == nil or run.opts.target == lang) then
      r[#r + 1] = run
    end
  end
  return r
end

--- What was sent to a room, in order.
local function sent_to(key)
  local r = {}
  for _, s in ipairs(sent) do
    if s.target == key then
      r[#r + 1] = s
    end
  end
  return r
end

describe("the tabs of other display languages: registering them", function()
  before_each(install)
  after_each(restore)

  it("a tab is the room the preview follows plus its language", function()
    assert.are.equal(MAIN .. "#es", rooms.add("es"))
    assert.are.equal(MAIN .. "#it", rooms.add("it"))
    assert.are.equal(MAIN .. "#es", rooms.add("es"), "the same language is the same tab")
    local list = rooms.list()
    assert.are.same({ "es", "it" }, { list[1].code, list[2].code })
  end)

  it("refuses what it cannot serve and says why", function()
    local key, err = rooms.add("not a code")
    assert.is_nil(key)
    assert.is_truthy(err:find("language code", 1, true))
    state.set_preview_key(nil)
    key, err = rooms.add("es")
    assert.is_nil(key)
    assert.is_truthy(err:find("no preview tab", 1, true))
    state.set_preview_key(MAIN)
    config.defaults.browser.behavior = "new_tab"
    key, err = rooms.add("es")
    assert.is_nil(key)
    assert.is_truthy(err:find("reuse", 1, true))
  end)

  it("repeats what is sent to the preview room into its followers, and nothing else", function()
    rooms.add("es")
    rooms.add("it")
    assert.are.same({ MAIN .. "#es", MAIN .. "#it" }, rooms.followers(MAIN))
    assert.are.same({}, rooms.followers(MAIN .. "#es"), "a tab of a language is not repeated into the others")
    assert.are.same({}, rooms.followers("another/room"))
    assert.is_true(rooms.is_lang_room(MAIN .. "#it"))
    assert.is_false(rooms.is_lang_room(MAIN))
  end)

  it("forgets one or all, and a stopped session forgets them", function()
    rooms.add("es")
    rooms.add("it")
    assert.are.equal(1, rooms.remove("es"))
    assert.are.same({ MAIN .. "#it" }, rooms.followers(MAIN))
    assert.are.equal(0, rooms.remove("xx"))
    assert.are.equal(1, rooms.remove(nil))
    assert.are.same({}, rooms.list())
    rooms.add("de")
    rooms.reset()
    assert.are.same({}, rooms.followers(MAIN))
  end)
end)

describe("the tabs of other display languages: the text", function()
  local a, b
  before_each(function()
    install()
    a = make_buf("mdview_spec_lang_rooms_A.md", { "a-eins", "a-zwei" })
    b = make_buf("mdview_spec_lang_rooms_B.md", { "b-eins", "b-zwei" })
    require("mdview.core.session").init()
    rooms.add("es")
    rooms.add("it")
  end)
  after_each(function()
    restore()
    pcall(vim.api.nvim_buf_delete, a, { force = true })
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end)

  it("each language gets its own translation of the same document, the preview room the original", function()
    live.push_buffer_changes(a, { full = true, reason = "save" })
    assert.is_true(settle(function()
      return #full_runs("es") == 1 and #full_runs("it") == 1
    end))
    -- The preview tab: the buffer as it is (no display_lang), one synchronous send.
    assert.are.same({ "a-eins", "a-zwei" }, sent_to(MAIN)[1].lines)
    full_runs("es")[1].cb(true, { "a-uno", "a-dos" }, { failed = 0 })
    full_runs("it")[1].cb(true, { "a-uno-it", "a-due" }, { failed = 0 })
    assert.is_true(settle(function()
      local es, it = sent_to(MAIN .. "#es"), sent_to(MAIN .. "#it")
      return #es >= 2 and #it >= 2 and es[#es].lines[1] == "a-uno" and it[#it].lines[1] == "a-uno-it"
    end))
    local es, it = sent_to(MAIN .. "#es"), sent_to(MAIN .. "#it")
    assert.are.same({ "a-uno", "a-dos" }, es[#es].lines)
    assert.are.same({ "a-uno-it", "a-due" }, it[#it].lines)
    for _, s in ipairs(sent) do
      assert.are.equal(2, #s.lines, "a translation keeps the lines")
    end
    -- Never the text of one language in the room of the other.
    for _, s in ipairs(es) do
      assert.are_not.equal("a-uno-it", s.lines[1])
    end
    for _, s in ipairs(it) do
      assert.are_not.equal("a-uno", s.lines[1])
    end
    assert.are.same({ "a-eins", "a-zwei" }, vim.api.nvim_buf_get_lines(a, 0, -1, false), "the buffer is untouched")
  end)

  it("a switch of the buffer is a switch in every tab, and a late answer of the old one is dropped", function()
    assert.is_true(buffer_switch.resync(a))
    assert.is_true(settle(function()
      return #full_runs("es") == 1 and #full_runs("it") == 1
    end))
    local a_es, a_it = full_runs("es")[1], full_runs("it")[1]
    assert.is_true(buffer_switch.resync(b))
    assert.is_true(settle(function()
      return #full_runs("es") == 2 and #full_runs("it") == 2
    end))
    a_es.cb(true, { "A-UNO", "A-DOS" }, { failed = 0 })
    a_it.cb(true, { "A-UNO-IT", "A-DUE" }, { failed = 0 })
    full_runs("es")[2].cb(true, { "B-UNO", "B-DOS" }, { failed = 0 })
    full_runs("it")[2].cb(true, { "B-UNO-IT", "B-DUE" }, { failed = 0 })
    assert.is_true(settle(function()
      local es, it = sent_to(MAIN .. "#es"), sent_to(MAIN .. "#it")
      return es[#es].lines[1] == "B-UNO" and it[#it].lines[1] == "B-UNO-IT"
    end))
    for _, s in ipairs(sent) do
      assert.are_not.equal("A-UNO", s.lines[1])
      assert.are_not.equal("A-UNO-IT", s.lines[1])
    end
  end)

  it("a tab that is closed gets nothing more", function()
    live.push_buffer_changes(a, { full = true, reason = "save" })
    assert.is_true(settle(function()
      return #full_runs("es") == 1
    end))
    rooms.remove("es")
    local before = #sent_to(MAIN .. "#es")
    full_runs("es")[1].cb(true, { "a-uno", "a-dos" }, { failed = 0 })
    live.push_buffer_changes(a, { full = true, reason = "save" })
    vim.wait(100, function()
      return false
    end, 10)
    assert.are.equal(before, #sent_to(MAIN .. "#es"))
  end)

  it("keeps a state for each tab", function()
    live.push_buffer_changes(a, { full = true, reason = "save" })
    assert.is_true(settle(function()
      return #full_runs("es") == 1 and #full_runs("it") == 1
    end))
    local st = display.statuses()
    assert.are.equal("es", st[MAIN .. "#es"].lang)
    assert.are.equal("it", st[MAIN .. "#it"].lang)
    assert.are.equal("translating", st[MAIN .. "#es"].state)
    assert.are.equal("off", display.status().state, "the state of the display language is not that of a tab")
    full_runs("es")[1].cb(true, { "a-uno", "a-dos" }, { failed = 0 })
    assert.is_true(settle(function()
      return display.statuses()[MAIN .. "#es"].state == "done"
    end))
    assert.are.equal("translating", display.statuses()[MAIN .. "#it"].state, "the other tab is still at work")
  end)
end)

describe("the tabs of other display languages: what follows the preview", function()
  before_each(function()
    install()
    rooms.add("es")
  end)
  after_each(restore)

  it("the live controls reach the tabs of other languages, the badge of a room stays its own", function()
    state.get_server = function()
      return { running = true }
    end
    local control = require("mdview.adapter.control")
    assert.is_true(control.send({ zoom = 1.2 }, MAIN))
    local keys = {}
    for _, c in ipairs(controls) do
      keys[#keys + 1] = c.key
    end
    assert.are.same({ MAIN, MAIN .. "#es" }, keys)
    controls = {}
    assert.is_true(control.send({ displayLang = { state = "done" } }, MAIN))
    assert.are.equal(1, #controls, "the badge is not repeated")
    assert.are.equal(MAIN, controls[1].key)
  end)

  it("the scroll position reaches them as well", function()
    ws.send_scroll(MAIN, 3, 10, 0.5, 2)
    local urls = {}
    for _, cmd in ipairs(posts) do
      for _, part in ipairs(cmd) do
        if type(part) == "string" and part:find("/scroll?key=", 1, true) then
          urls[#urls + 1] = part
        end
      end
    end
    assert.are.equal(2, #urls)
    assert.is_truthy(urls[1]:find(vim.uri_encode(MAIN, "rfc2396") .. "&", 1, true))
    assert.is_truthy(urls[2]:find(vim.uri_encode(MAIN .. "#es", "rfc2396") .. "&", 1, true))
  end)
end)

describe(":MDView lang open / close / tabs", function()
  local lang = require("mdview.bindings.usrcmds.lang")
  local notes
  before_each(function()
    install()
    notes = {}
    vim.notify = function(msg, level)
      notes[#notes + 1] = { msg = msg, level = level }
    end
  end)
  after_each(restore)

  it("lists the tabs and their state, and says when there is none", function()
    lang.run("tabs")
    assert.is_truthy(notes[#notes].msg:find("no tab of another language", 1, true))
    rooms.add("es")
    lang.run("tabs")
    assert.is_truthy(notes[#notes].msg:find("es", 1, true))
    lang.run("")
    assert.is_truthy(notes[#notes].msg:find("tabs of other languages: es", 1, true), "the report names them too")
  end)

  it("open needs a code and a language.nvim that can translate", function()
    lang.run("open")
    assert.are.equal(vim.log.levels.WARN, notes[#notes].level)
    assert.is_truthy(notes[#notes].msg:find("name a language", 1, true))
    package.loaded["language"] = nil
    package.preload["language"] = nil
    lang.run("open", "es")
    assert.are.equal(vim.log.levels.WARN, notes[#notes].level)
    assert.is_truthy(notes[#notes].msg:find("language.nvim", 1, true))
    assert.are.same({}, rooms.list())
  end)

  it("open es and open es again is one tab; `open es` as one argument works", function()
    state.get_server = function()
      return { running = true }
    end
    local opened = {}
    local browser = require("mdview.adapter.browser")
    local real_open = browser.open
    browser.open = function(url)
      opened[#opened + 1] = url
      return { id = #opened }
    end
    local attached, token = state.is_attached, state.get_token
    state.is_attached = function()
      return true
    end
    state.get_token = function()
      return "t"
    end
    lang.run("open es")
    lang.run("open", "es")
    browser.open = real_open
    state.is_attached, state.get_token = attached, token
    assert.are.equal(2, #opened, "the browser is asked for a tab each time")
    assert.are.equal(1, #rooms.list(), "but the room is one")
    assert.is_truthy(opened[1]:find(vim.uri_encode(MAIN .. "#es", "rfc2396"), 1, true))
  end)

  it("close forgets one or all", function()
    rooms.add("es")
    rooms.add("it")
    lang.run("close", "es")
    assert.are.equal(1, #rooms.list())
    lang.run("close all")
    assert.are.equal(0, #rooms.list())
    lang.run("close", "xx")
    assert.is_truthy(notes[#notes].msg:find("no such tab", 1, true))
  end)
end)

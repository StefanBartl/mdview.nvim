---@module 'tests.nvim.display_spec'
-- The display transform (core/display.lua): `browser.transform` and
-- `browser.display_lang`, with language.nvim replaced by a fake translator that
-- the spec drives by hand (no network, no timers: a run finishes when the spec
-- says so).
--
-- What is pinned down: no transform answers synchronously and unchanged; the
-- line invariant; stale results (fast edits, a buffer or tab switch in "reuse"
-- mode, where the room is shared) are never shown; the cache-only text comes
-- first, patches next, the finished document last; every failure leaves the
-- original and speaks once; the triggers; the off switch.

---@diagnostic disable: undefined-global, duplicate-set-field

local display = require("mdview.core.display")
local config = require("mdview.config")

--- A scripted language.nvim: records every call and finishes runs on demand.
---@return table fake
local function make_fake()
  local fake = { calls = {}, cache = {} }
  fake.translate_markdown = function(lines, opts, cb)
    local call = { lines = lines, opts = opts, cb = cb, cancelled = false }
    fake.calls[#fake.calls + 1] = call
    call.handle = {
      cancel = function()
        if call.finished then
          return
        end
        call.cancelled = true
        call.finished = true
        cb(false, "cancelled")
      end,
    }
    if opts.cache_only then
      -- Like language.nvim: answers later (never before the call returned),
      -- cached lines translated, the rest original.
      vim.schedule(function()
        if call.finished then
          return
        end
        call.finished = true
        local out = {}
        for i, l in ipairs(lines) do
          out[i] = fake.cache[l] or l
        end
        cb(true, out, { pending = 0 })
      end)
    end
    function call.unit(first, last, translated)
      opts.on_unit({ first = first, last = last, lines = translated, status = "translated", done = 1, total = 2 })
    end
    function call.finish(result, info)
      call.finished = true
      cb(true, result, info or { failed = 0 })
    end
    function call.fail(msg)
      call.finished = true
      cb(false, msg)
    end
    return call.handle
  end
  --- The runs that are not cache-only, i.e. the ones that ask an engine.
  function fake.full()
    local r = {}
    for _, c in ipairs(fake.calls) do
      if not c.opts.cache_only then
        r[#r + 1] = c
      end
    end
    return r
  end
  return fake
end

local saved = {}
local fake
local notes

--- Everything the spec changes is put back by `teardown`.
local function setup_env(browser)
  saved.loaded = {
    language = package.loaded["language"],
    ["language.config"] = package.loaded["language.config"],
    registry = package.loaded["language.translate.providers.registry"],
  }
  saved.preload = package.preload["language"]
  saved.notify = vim.notify
  saved.browser = vim.deepcopy(config.defaults.browser)
  fake = make_fake()
  package.loaded["language"] = fake
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
  notes = {}
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = msg, level = level }
  end
  local b = config.defaults.browser
  b.display_lang, b.transform, b.display_lang_trigger, b.display_lang_debounce_ms = nil, nil, "idle", 800
  b.display_lang_source, b.display_lang_engine = nil, nil
  for k, v in pairs(browser or {}) do
    b[k] = v
  end
  display.reset()
end

local function teardown_env()
  display.reset()
  package.loaded["language"] = saved.loaded.language
  package.loaded["language.config"] = saved.loaded["language.config"]
  package.loaded["language.translate.providers.registry"] = saved.loaded.registry
  package.preload["language"] = saved.preload
  vim.notify = saved.notify
  local b = config.defaults.browser
  for _, k in ipairs({ "display_lang", "transform", "display_lang_source", "display_lang_engine" }) do
    b[k] = saved.browser[k]
  end
  b.display_lang_trigger = saved.browser.display_lang_trigger
  b.display_lang_debounce_ms = saved.browser.display_lang_debounce_ms
end

---@return boolean
local function settle(cond)
  return vim.wait(500, cond, 5)
end

--- Collects what a stream delivers.
local function collector()
  local got = { texts = {}, finals = {} }
  got.fn = function(out, final)
    got.texts[#got.texts + 1] = vim.deepcopy(out)
    got.finals[#got.finals + 1] = final
  end
  return got
end

local function count_notes(pattern)
  local n = 0
  for _, note in ipairs(notes) do
    if note.msg:find(pattern, 1, true) then
      n = n + 1
    end
  end
  return n
end

describe("display.stream without a transform", function()
  before_each(function()
    setup_env()
  end)
  after_each(teardown_env)

  it("answers synchronously, once, with the very text it got", function()
    local lines = { "# Titel", "Text" }
    local got = collector()
    local transformed = display.stream({ path = "a.md", target = "a.md" }, lines, got.fn)
    assert.is_false(transformed)
    assert.are.equal(1, #got.texts)
    assert.are.same(lines, got.texts[1])
    assert.is_true(got.finals[1])
    assert.is_false(display.active())
  end)
end)

describe("display.stream with browser.transform", function()
  before_each(function()
    setup_env()
  end)
  after_each(teardown_env)

  it("shows the original at once, then the hook's text, with the same line count", function()
    config.defaults.browser.transform = function(lines, ctx, cb)
      local out = {}
      for i, l in ipairs(lines) do
        out[i] = l:upper()
      end
      assert.are.equal("a.md", ctx.path)
      cb(out)
    end
    local got = collector()
    display.stream({ path = "a.md", target = "a.md", reason = "switch" }, { "ab", "cd" }, got.fn)
    assert.are.same({ "ab", "cd" }, got.texts[1])
    assert.is_false(got.finals[1])
    assert.is_true(settle(function()
      return #got.texts >= 2
    end))
    assert.are.same({ "AB", "CD" }, got.texts[#got.texts])
    assert.is_true(got.finals[#got.finals])
  end)

  it("drops a result with another line count and speaks once", function()
    config.defaults.browser.transform = function(_, _, cb)
      cb({ "only one" })
    end
    local got = collector()
    for _ = 1, 2 do
      display.stream({ path = "a.md", target = "a.md", reason = "switch" }, { "x", "y" }, got.fn)
      assert.is_true(settle(function()
        return got.finals[#got.finals] == true
      end))
    end
    for _, t in ipairs(got.texts) do
      assert.are.same({ "x", "y" }, t, "never a document of another length")
    end
    assert.are.equal(1, count_notes("exactly as many lines"))
  end)

  it("a hook that raises or answers with garbage leaves the original", function()
    config.defaults.browser.transform = function()
      error("boom")
    end
    local got = collector()
    display.stream({ path = "a.md", target = "a.md", reason = "switch" }, { "x" }, got.fn)
    assert.are.same({ "x" }, got.texts[#got.texts])
    assert.are.equal(1, count_notes("browser.transform failed"))

    config.defaults.browser.transform = function(_, _, cb)
      cb({ 42 })
    end
    got = collector()
    display.stream({ path = "a.md", target = "a.md", reason = "switch" }, { "x" }, got.fn)
    assert.are.same({ "x" }, got.texts[#got.texts])
  end)

  it("ignores a second cb call of the hook", function()
    local seen = 0
    config.defaults.browser.transform = function(lines, _, cb)
      cb(vim.deepcopy(lines))
      cb({ "late" })
    end
    local got = collector()
    display.stream({ path = "a.md", target = "a.md", reason = "switch" }, { "x" }, function(out, final)
      if final then
        seen = seen + 1
      end
      got.fn(out, final)
    end)
    assert.are.equal(1, seen)
    assert.are.same({ "x" }, got.texts[#got.texts])
  end)

  it("discards a late answer after a newer push to the same room (fast edit)", function()
    local pending = {}
    config.defaults.browser.transform = function(lines, _, cb)
      pending[#pending + 1] = { lines = lines, cb = cb }
    end
    local got = collector()
    display.stream({ path = "a.md", target = "room", reason = "switch" }, { "one" }, got.fn)
    display.stream({ path = "a.md", target = "room", reason = "switch" }, { "two" }, got.fn)
    assert.are.equal(2, #pending)
    pending[2].cb({ "TWO" })
    pending[1].cb({ "ONE" }) -- the older run answers last
    for _, t in ipairs(got.texts) do
      assert.are_not.same({ "ONE" }, t)
    end
    assert.are.same({ "TWO" }, got.texts[#got.texts])
  end)

  it("never shows one document's result for another in a shared room (tab switch)", function()
    local pending = {}
    config.defaults.browser.transform = function(lines, ctx, cb)
      pending[ctx.path] = { lines = lines, cb = cb }
    end
    local got = collector()
    display.stream({ path = "A.md", target = "preview-room", reason = "switch" }, { "a1", "a2" }, got.fn)
    display.stream({ path = "B.md", target = "preview-room", reason = "switch" }, { "b1", "b2" }, got.fn)
    pending["A.md"].cb({ "A1", "A2" })
    pending["B.md"].cb({ "B1", "B2" })
    for _, t in ipairs(got.texts) do
      assert.are_not.same({ "A1", "A2" }, t)
    end
    assert.are.same({ "B1", "B2" }, got.texts[#got.texts])
  end)

  it("the immediate text is the document's own last output, not another document's", function()
    config.defaults.browser.transform = function(lines, _, cb)
      local out = {}
      for i, l in ipairs(lines) do
        out[i] = "<" .. l .. ">"
      end
      cb(out)
    end
    local got = collector()
    display.stream({ path = "A.md", target = "room", reason = "switch" }, { "a" }, got.fn)
    display.stream({ path = "B.md", target = "room", reason = "switch" }, { "b" }, got.fn)
    got = collector()
    display.stream({ path = "A.md", target = "room", reason = "switch" }, { "a" }, got.fn)
    assert.are.same({ "<a>" }, got.texts[1], "A comes back with A's own last output")
    local got_b = collector()
    display.stream({ path = "B.md", target = "room", reason = "switch" }, { "b" }, got_b.fn)
    assert.are.same({ "<b>" }, got_b.texts[1])
  end)

  it("uses the same hook under display_lang (the hook sees the translated text)", function()
    config.defaults.browser.display_lang = "en"
    local ctx_lang
    config.defaults.browser.transform = function(lines, ctx, cb)
      ctx_lang = ctx.display_lang
      local out = {}
      for i, l in ipairs(lines) do
        out[i] = l .. "!"
      end
      cb(out)
    end
    fake.cache["hallo"] = "hello"
    local got = collector()
    display.stream({ path = "a.md", target = "a.md", reason = "switch" }, { "hallo" }, got.fn)
    assert.is_true(settle(function()
      return #got.texts >= 1
    end))
    assert.are.same({ "hello!" }, got.texts[1])
    assert.are.equal("en", ctx_lang)
  end)
end)

describe("display.stream with display_lang", function()
  before_each(function()
    setup_env({ display_lang = "en", display_lang_debounce_ms = 20 })
  end)
  after_each(teardown_env)

  local function run(reason, lines, target, path)
    local got = collector()
    display.stream({ path = path or "a.md", target = target or "a.md", reason = reason }, lines, got.fn)
    return got
  end

  it("paints the cache-only text first, patches next, the finished document last", function()
    fake.cache["Hallo Welt"] = "Hello world"
    local lines = { "# Titel", "Hallo Welt", "Neu" }
    local got = run("switch", lines)
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    assert.are.same({ "# Titel", "Hello world", "Neu" }, got.texts[1])
    assert.is_false(got.finals[1])

    local call = fake.full()[1]
    assert.are.equal("en", call.opts.target)
    call.unit(1, 1, { "# Title" })
    assert.is_true(settle(function()
      return #got.texts >= 2
    end))
    assert.are.same({ "# Title", "Hello world", "Neu" }, got.texts[2])
    assert.is_false(got.finals[2])

    call.finish({ "# Title", "Hello world", "New" }, { failed = 0 })
    assert.is_true(settle(function()
      return got.finals[#got.finals] == true
    end))
    assert.are.same({ "# Title", "Hello world", "New" }, got.texts[#got.texts])
    for _, t in ipairs(got.texts) do
      assert.are.equal(#lines, #t, "every text keeps the line count")
    end
    assert.are.equal("done", display.status().state)
  end)

  it("a malformed patch is skipped, the final result still decides", function()
    local got = run("switch", { "a", "b" })
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    local call = fake.full()[1]
    call.unit(1, 2, { "only one" }) -- 1 line for a 2-line range
    call.unit(3, 3, { "out of range" })
    call.unit(0, 0, { "zero" })
    vim.wait(200, function()
      return false
    end, 20)
    assert.are.equal(1, #got.texts, "nothing was patched in")
    call.finish({ "A", "B" })
    assert.is_true(settle(function()
      return got.finals[#got.finals] == true
    end))
    assert.are.same({ "A", "B" }, got.texts[#got.texts])
  end)

  it("a result of another length becomes the original, reported once", function()
    local got = run("switch", { "a", "b" })
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    fake.full()[1].finish({ "only" })
    assert.is_true(settle(function()
      return got.finals[#got.finals] == true
    end))
    assert.are.same({ "a", "b" }, got.texts[#got.texts])
    assert.are.equal(1, count_notes("did not keep the line count"))
    assert.are.equal("failed", display.status().state)
  end)

  it("an engine failure leaves the original and speaks once", function()
    local got = run("switch", { "a" })
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    fake.full()[1].fail("no available translate engine (tried: ai)")
    assert.is_true(settle(function()
      return got.finals[#got.finals] == true
    end))
    assert.are.same({ "a" }, got.texts[#got.texts])
    run("switch", { "a" })
    assert.is_true(settle(function()
      return #fake.full() == 2
    end))
    fake.full()[2].fail("no available translate engine (tried: ai)")
    vim.wait(100, function()
      return false
    end, 10)
    assert.are.equal(1, count_notes("no available translate engine"), "the same message is not repeated")
  end)

  it("unit failures that stayed original are reported once, the document is shown", function()
    local got = run("switch", { "a", "b" })
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    fake.full()[1].finish({ "A", "b" }, { failed = 1, errors = { "429 too many requests" } })
    assert.is_true(settle(function()
      return got.finals[#got.finals] == true
    end))
    assert.are.same({ "A", "b" }, got.texts[#got.texts])
    assert.are.equal(1, count_notes("stay original"))
  end)

  it("drops the result of an older generation and cancels its run (fast edits)", function()
    local first = run("switch", { "a" })
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    local old = fake.full()[1]
    local second = run("switch", { "ab" })
    assert.is_true(old.cancelled, "the older run is cancelled")
    assert.is_true(settle(function()
      return #fake.full() == 2
    end))
    old.finish({ "OLD" }) -- a late answer from the abandoned run
    fake.full()[2].finish({ "AB" })
    assert.is_true(settle(function()
      return second.finals[#second.finals] == true
    end))
    for _, t in ipairs(first.texts) do
      assert.are_not.same({ "OLD" }, t)
    end
    for _, t in ipairs(second.texts) do
      assert.are_not.same({ "OLD" }, t)
    end
    assert.are.same({ "AB" }, second.texts[#second.texts])
  end)

  it("a buffer switch in reuse mode never shows the previous document's translation", function()
    local a = run("switch", { "a1", "a2" }, "preview-room", "A.md")
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    local a_run = fake.full()[1]
    local b = run("switch", { "b1", "b2" }, "preview-room", "B.md")
    a_run.unit(1, 1, { "A-PATCH" })
    a_run.finish({ "A1", "A2" })
    assert.is_true(settle(function()
      return #fake.full() == 2
    end))
    fake.full()[2].finish({ "B1", "B2" })
    assert.is_true(settle(function()
      return b.finals[#b.finals] == true
    end))
    for _, t in ipairs(b.texts) do
      assert.are_not.same({ "A1", "A2" }, t)
      assert.are_not.same({ "A-PATCH", "a2" }, t)
    end
    assert.are.same({ "B1", "B2" }, b.texts[#b.texts])
    for _, t in ipairs(a.texts) do
      assert.are_not.same({ "A1", "A2" }, t, "the abandoned run delivered nothing")
    end
  end)

  it("idle: an edit starts the full run only after the pause, and a newer edit restarts it", function()
    config.defaults.browser.display_lang_debounce_ms = 80
    run("edit", { "a" })
    run("edit", { "ab" })
    assert.are.equal(0, #fake.full(), "nothing asked the engine yet")
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    assert.are.same({ "ab" }, fake.full()[1].lines, "only the latest text goes out")
  end)

  it("save: an edit never asks the engine, a save does", function()
    config.defaults.browser.display_lang_trigger = "save"
    local got = run("edit", { "a" })
    assert.is_true(settle(function()
      return #got.texts >= 1
    end))
    vim.wait(150, function()
      return false
    end, 10)
    assert.are.equal(0, #fake.full())
    assert.are.same({ "a" }, got.texts[1], "still a valid text")
    run("save", { "a" })
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
  end)

  it("manual: only enable/refresh ask the engine", function()
    config.defaults.browser.display_lang_trigger = "manual"
    run("edit", { "a" })
    run("switch", { "a" })
    run("save", { "a" })
    vim.wait(150, function()
      return false
    end, 10)
    assert.are.equal(0, #fake.full())
    run("refresh", { "a" })
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
  end)

  it("never goes to the engine per keystroke: cache-only runs never ask it", function()
    for i = 1, 5 do
      run("edit", { "x" .. i })
    end
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    for _, c in ipairs(fake.calls) do
      if c.opts.cache_only then
        assert.is_nil(c.opts.on_unit)
      end
    end
    assert.are.equal(1, #fake.full(), "five edits, one request run")
  end)

  it("names the engine in the opt-in notice, once per session", function()
    run("switch", { "a" })
    run("switch", { "b" })
    assert.are.equal(1, count_notes('"fakeengine"'))
    assert.are.equal(1, count_notes("may leave this machine"))
  end)

  it("without language.nvim: the original, one warning, never an error", function()
    package.loaded["language"] = nil
    package.preload["language"] = function()
      error("module 'language' not found")
    end
    local got = run("switch", { "a" })
    assert.are.same({ "a" }, got.texts[1])
    assert.is_true(got.finals[1])
    run("switch", { "a" })
    assert.are.equal(1, count_notes("language.nvim"))
    assert.are.equal("unavailable", display.status().state)
  end)

  it("a bad option value is reported once and means off", function()
    config.defaults.browser.display_lang = 42
    assert.is_nil(display.lang())
    assert.is_nil(display.lang())
    assert.are.equal(1, count_notes("display_lang must be a language code"))
    config.defaults.browser.display_lang_trigger = "sometimes"
    assert.are.equal("idle", display.trigger())
  end)

  it("off restores the original at once and nothing arrives afterwards", function()
    local got = run("switch", { "a" })
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    local call = fake.full()[1]
    local ok = display.set_lang(nil)
    assert.is_true(ok)
    assert.is_true(call.cancelled)
    assert.is_nil(display.lang())
    local after = collector()
    local transformed = display.stream({ path = "a.md", target = "a.md", reason = "enable" }, { "a" }, after.fn)
    assert.is_false(transformed)
    assert.are.same({ "a" }, after.texts[1], "synchronous, the original")
    call.finish({ "LATE" })
    for _, t in ipairs(got.texts) do
      assert.are_not.same({ "LATE" }, t)
    end
  end)

  it("a fixture document keeps its line count and its fences byte for byte", function()
    local fixture = {
      "---",
      "title: Anleitung",
      "---",
      "# Einleitung",
      "",
      "Ein Absatz mit `Code` und [Link](#einleitung).",
      "",
      "| Name | Wert |",
      "| ---- | ---- |",
      "| eins | zwei |",
      "",
      "- [ ] Aufgabe",
      "- [x] Erledigt",
      "",
      "> Zitat",
      "",
      "```lua",
      'print("Hallo")',
      "```",
    }
    local got = run("switch", fixture)
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    local out = vim.deepcopy(fixture)
    out[4], out[6], out[15] = "# Introduction", "A paragraph with `Code` and [Link](#introduction).", "> Quote"
    fake.full()[1].finish(out)
    assert.is_true(settle(function()
      return got.finals[#got.finals] == true
    end))
    local final = got.texts[#got.texts]
    assert.are.equal(#fixture, #final)
    for i = 17, 19 do
      assert.are.equal(fixture[i], final[i])
    end
    assert.are.equal("# Introduction", final[4])
  end)
end)

describe("display.status and the browser badge", function()
  before_each(function()
    setup_env({ display_lang = "en" })
  end)
  after_each(teardown_env)

  it("goes through translating to done and is sent to the browser as a control message", function()
    local control = require("mdview.adapter.control")
    local orig = control.send
    local sent = {}
    control.send = function(fields)
      sent[#sent + 1] = fields
      return true
    end
    local got = collector()
    display.stream({ path = "a.md", target = "a.md", reason = "switch" }, { "a" }, got.fn)
    assert.is_true(settle(function()
      return #fake.full() == 1
    end))
    assert.are.equal("translating", display.status().state)
    fake.full()[1].finish({ "A" })
    assert.is_true(settle(function()
      return display.status().state == "done"
    end))
    control.send = orig
    local states = {}
    for _, f in ipairs(sent) do
      states[#states + 1] = f.displayLang and f.displayLang.state
    end
    -- "done" is said once on the change and again with the finished document
    -- (a tab opened in between has not seen the first one).
    assert.are.same({ "translating", "done", "done" }, states)
    assert.are.equal("fakeengine", sent[2].displayLang.engine)
    assert.are.equal("en", sent[2].displayLang.lang)
  end)
end)

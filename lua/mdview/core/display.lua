---@module 'mdview.core.display'
--- The display transform: the text the preview shows may differ from the text
--- of the buffer, as long as it has exactly as many lines.
---
--- Two consumers share one pipeline:
---
---   * `browser.display_lang = "en"` -- the buffer stays German, the preview
---     shows the English translation. The translation itself is not done here:
---     it belongs to language.nvim (`translate_markdown`), looked up with
---     `pcall(require)` and never a hard dependency.
---   * `browser.transform = function(lines, ctx, cb)` -- the generic hook. It
---     knows nothing about translation; `cb(new_lines)` may be called later (or
---     never, then the document stays as it was shown last).
---
--- Every push into the preview goes through `M.stream` (via
--- `mirror.lines_async`). Without a transform it answers synchronously with the
--- text as it is, so a plain session behaves exactly as before.
---
--- Rules the pipeline keeps:
---
---   * Line invariant: `#out == #in`. Scroll sync, the cursor marker,
---     click-to-navigate, checkbox sync and the fence spans all address lines of
---     the document; a result of another length is dropped (the original is
---     shown instead) and reported once.
---   * Stale-while-revalidate: something valid is sent at once (the cached
---     translation of every unchanged paragraph, the rest original), the
---     paragraphs that are translated afterwards are patched in as they finish,
---     and the finished document is sent last.
---   * Generations: every stream bumps a counter of its TARGET ROOM. A result
---     that belongs to an older generation (fast edits, a buffer or tab switch
---     in "reuse" mode, where every document shares the room of the one tab) is
---     discarded, so one document's translation is never shown for another.
---   * Never broken: any failure leaves the original visible and is reported
---     once, never an empty or half document.
---   * Never silent about privacy: the first time a translation is used in a
---     session, the message names the engine the text goes to.

local M = {}

local notify = require("lib.nvim.notify").create("").notify

--- Debounce of the `idle` trigger when the option is unset.
M.DEFAULT_DEBOUNCE_MS = 800

--- How long progressive patches are coalesced into one push.
local PATCH_MS = 150

---@type table<string, boolean>
M.TRIGGERS = { idle = true, save = true, manual = true }

--- Per target room: generation, the run in flight and its timers.
---@class mdview.display.Room
---@field gen integer
---@field handle { cancel: fun() }|nil # language.nvim run in flight
---@field timer uv.uv_timer_t|nil # debounce of the full run
---@field patch_pending boolean
---@field hseq integer # sequence of the hook calls, only the latest counts

---@type table<string, mdview.display.Room>
local rooms = {}

--- The last output per SOURCE PATH, for the hook-only case. The room of the
--- one preview tab is shared by every document in "reuse" mode, so a cache
--- keyed by room would hand one document the output of another.
---@type table<string, { n: integer, out: string[] }>
local last = {}

---@type table<string, boolean>
local reported = {}
local privacy_noted = false

---@class mdview.display.Status
---@field state "off"|"idle"|"translating"|"done"|"failed"|"unavailable"
---@field lang string|nil
---@field engine string|nil
---@field done integer|nil
---@field total integer|nil
---@field message string|nil
---@type mdview.display.Status
local status = { state = "off" }
local status_sent = ""

---@internal
---@return table
local function browser_cfg()
  return require("mdview.config").defaults.browser
end

--- Report a problem once per distinct message (until the option changes).
---@internal
---@param msg string
---@param level integer|nil
---@return nil
local function report_once(msg, level)
  if reported[msg] then
    return
  end
  reported[msg] = true
  notify("[mdview] " .. msg, level or vim.log.levels.WARN)
end

---@internal
---@param t table|nil
---@return string[]
local function copy(t)
  return vim.list_slice(t or {})
end

---@param v any
---@param n integer
---@return boolean
local function valid_lines(v, n)
  if type(v) ~= "table" or #v ~= n then
    return false
  end
  for i = 1, n do
    if type(v[i]) ~= "string" then
      return false
    end
  end
  return true
end

--- The configured display language, or nil when the option is off or not a
--- usable language code (a malformed value is reported once and means off).
---@return string|nil
function M.lang()
  local v = browser_cfg().display_lang
  if v == nil or v == false or v == "" then
    return nil
  end
  if type(v) ~= "string" or not v:match("^%a[%w_%-]*$") or #v > 16 then
    report_once('browser.display_lang must be a language code such as "en", got ' .. vim.inspect(v))
    return nil
  end
  return v
end

--- The configured trigger of the full run: "idle" (default), "save", "manual".
---@return "idle"|"save"|"manual"
function M.trigger()
  local v = browser_cfg().display_lang_trigger
  if v == nil then
    return "idle"
  end
  if type(v) ~= "string" or not M.TRIGGERS[v] then
    report_once("browser.display_lang_trigger must be one of idle, save, manual, got " .. vim.inspect(v))
    return "idle"
  end
  return v
end

--- Debounce of the `idle` trigger in milliseconds.
---@return integer
function M.debounce_ms()
  local v = browser_cfg().display_lang_debounce_ms
  if type(v) ~= "number" or v < 0 or v ~= v then
    if v ~= nil then
      report_once("browser.display_lang_debounce_ms must be a number >= 0, got " .. vim.inspect(v))
    end
    return M.DEFAULT_DEBOUNCE_MS
  end
  return math.floor(v)
end

---@internal
---@return function|nil
local function hook()
  local f = browser_cfg().transform
  if f == nil then
    return nil
  end
  if type(f) ~= "function" then
    report_once("browser.transform must be a function(lines, ctx, cb), got " .. type(f))
    return nil
  end
  return f
end

--- Whether the preview text may differ from the buffer text right now.
--- Reverse paths that write text back (text-field sync) must stay off then.
---@return boolean
function M.active()
  return M.lang() ~= nil or hook() ~= nil
end

--- language.nvim, or nil when it is not installed (or too old to translate
--- Markdown). Looked up on use, never loaded eagerly.
---@return table|nil
function M.language()
  local ok, lang = pcall(require, "language")
  if ok and type(lang) == "table" and type(lang.translate_markdown) == "function" then
    return lang
  end
  return nil
end

---@class mdview.display.EngineInfo
---@field found boolean # language.nvim is installed
---@field engine string|nil # the engine the text would go to
---@field available boolean
---@field err string|nil

--- What language.nvim would use right now. Reads its configuration and asks its
--- registry, which also follows its fallback chain, so the engine named here is
--- the one the text really goes to. Never exposes a key, only whether it works.
---@return mdview.display.EngineInfo
function M.engine_info()
  if not M.language() then
    return { found = false, available = false, err = "language.nvim not found" }
  end
  local ok_cfg, cfgmod = pcall(require, "language.config")
  local tr = ok_cfg and type(cfgmod.get) == "function" and cfgmod.get().translate or {}
  local override = browser_cfg().display_lang_engine
  if type(override) == "string" and override ~= "" then
    tr = vim.tbl_extend("force", tr, { engine = override, fallback = {} })
  end
  local ok_reg, reg = pcall(require, "language.translate.providers.registry")
  if not ok_reg or type(reg.resolve) ~= "function" then
    return { found = true, engine = tr.engine, available = false, err = "language.nvim has no engine registry" }
  end
  local ok_res, provider, err = pcall(reg.resolve, tr)
  if ok_res and provider then
    return { found = true, engine = provider.name or tr.engine, available = true }
  end
  return {
    found = true,
    engine = tr.engine,
    available = false,
    err = ok_res and err or tostring(provider),
  }
end

---@internal
---@param room_key string
---@return mdview.display.Room
local function room_of(room_key)
  local r = rooms[room_key]
  if not r then
    r = { gen = 0, patch_pending = false, hseq = 0 }
    rooms[room_key] = r
  end
  return r
end

---@internal
---@param r mdview.display.Room
---@return nil
local function cancel_room(r)
  if r.timer then
    r.timer:stop()
    pcall(function()
      r.timer:close()
    end)
    r.timer = nil
  end
  local h = r.handle
  r.handle = nil
  if h then
    pcall(h.cancel)
  end
  r.patch_pending = false
end

--- Tell the browser what state the preview is in (a small badge; an older
--- client ignores the message). Only sent when it changes.
---@internal
---@param force boolean|nil
---@return nil
local function push_status(force)
  local payload
  if status.state == "off" then
    payload = false
  else
    payload = {
      state = status.state,
      lang = status.lang,
      engine = status.engine,
      done = status.done,
      total = status.total,
      message = status.message,
    }
  end
  local ok, encoded = pcall(vim.json.encode, { displayLang = payload })
  if not ok then
    return
  end
  if not force and encoded == status_sent then
    return
  end
  status_sent = encoded
  pcall(require("mdview.adapter.control").send, { displayLang = payload })
end

---@internal
---@param s mdview.display.Status
---@return nil
local function set_status(s)
  status = s
  push_status(false)
end

--- The state of the display transform, for `:MDView lang` and `:checkhealth`.
---@return mdview.display.Status
function M.status()
  return vim.deepcopy(status)
end

--- Cancel everything in flight (switching the option, stopping the session).
--- Forgets what was reported, so the next activation speaks again.
---@param keep_notices boolean|nil # keep the privacy notice for this session
---@return nil
function M.reset(keep_notices)
  for _, r in pairs(rooms) do
    r.gen = r.gen + 1
    cancel_room(r)
  end
  last = {}
  reported = {}
  if not keep_notices then
    privacy_noted = false
  end
  status = { state = "off" }
  status_sent = ""
end

--- Whether `reason` starts the full (slow) run under the configured trigger.
---@internal
---@param reason string
---@return boolean run, boolean debounced
local function should_run(reason)
  local trigger = M.trigger()
  if reason == "enable" or reason == "refresh" then
    return true, false
  elseif reason == "edit" then
    return trigger == "idle", true
  end
  -- switch / initial / save
  return trigger ~= "manual", false
end

---@internal
---@param lang string
---@return nil
local function privacy_notice(lang)
  if privacy_noted then
    return
  end
  privacy_noted = true
  local info = M.engine_info()
  local engine = info.engine or "?"
  local msg = (
    "display_lang = %q: the text of the previewed document is sent to the translation engine %q "
    .. "(language.nvim) and may leave this machine. Nothing is sent while the option is off (`:MDView lang off`)."
  ):format(lang, engine)
  notify("[mdview] " .. msg, vim.log.levels.INFO)
end

---@class mdview.display.Source
---@field path string # source document (normalized path)
---@field target string # room the result goes to
---@field bufnr integer|nil
---@field reason "edit"|"save"|"switch"|"initial"|"enable"|"refresh"|nil

--- Pass a text through `browser.transform`, if there is one.
---@internal
---@param room mdview.display.Room
---@param is_stale fun(): boolean
---@param src mdview.display.Source
---@param out string[]
---@param final boolean
---@param k fun(res: string[])
---@return nil
local function through_hook(room, is_stale, src, out, final, k)
  local f = hook()
  if not f then
    k(out)
    return
  end
  room.hseq = room.hseq + 1
  local seq = room.hseq
  local done = false
  local ctx = {
    path = src.path,
    bufnr = src.bufnr,
    target = src.target,
    display_lang = M.lang(),
    reason = src.reason or "edit",
    final = final,
  }
  local function cb(res)
    if done then
      return
    end
    done = true
    if is_stale() or room.hseq ~= seq then
      return
    end
    if valid_lines(res, #out) then
      k(res)
    else
      report_once(
        "browser.transform must call cb with a list of exactly as many lines as it got ("
          .. #out
          .. "); the preview shows the text without it"
      )
      k(out)
    end
  end
  local ok, err = pcall(f, copy(out), ctx, cb)
  if not ok and not done then
    done = true
    report_once("browser.transform failed: " .. tostring(err))
    k(out)
  end
end

--- The text of `lines` as the preview should show it, delivered through
--- `on_text(out, final)`: synchronously and once when no transform is
--- configured, otherwise possibly several times (a first valid text, patches,
--- the finished document), all of them of the same length as `lines`.
---@param src mdview.display.Source
---@param lines string[]
---@param on_text fun(out: string[], final: boolean)
---@return boolean transformed # false: answered synchronously with `lines`
function M.stream(src, lines, on_text)
  local lang, f = M.lang(), hook()
  if not lang and not f then
    if status.state ~= "off" then
      M.reset(true)
    end
    on_text(lines, true)
    return false
  end

  local lib
  if lang then
    lib = M.language()
    if not lib then
      report_once("display_lang needs language.nvim, which was not found: the preview stays original")
      set_status({ state = "unavailable", lang = lang, message = "language.nvim not found" })
      lang = nil
      if not f then
        on_text(lines, true)
        return false
      end
    end
  end
  if lang then
    privacy_notice(lang)
  end

  local room = room_of(src.target)
  -- Bump first: cancelling a run calls its callback, which must find itself stale.
  room.gen = room.gen + 1
  cancel_room(room)
  local gen = room.gen
  local function is_stale()
    return room.gen ~= gen
  end

  local reason = src.reason or "edit"
  local do_run, debounced = should_run(reason)

  --- Deliver one text (through the hook) unless this generation is stale.
  local function deliver(out, final)
    if is_stale() then
      return
    end
    through_hook(room, is_stale, src, out, final, function(res)
      if is_stale() then
        return
      end
      if not lang and final then
        last[src.path] = { n = #res, out = copy(res) }
      end
      on_text(res, final)
      -- A tab opened after the last status change has not seen it: say it again
      -- with every finished document.
      if final and lang then
        push_status(true)
      end
    end)
  end

  --- The document as the full run left it, or the original when it failed.
  local function fail(msg)
    if is_stale() then
      return
    end
    report_once("display_lang: " .. msg .. "; the preview shows the original")
    set_status({ state = "failed", lang = lang, engine = status.engine, message = msg })
    deliver(lines, true)
  end

  if not lang then
    -- Hook only. Show the last output of this document at once when it still
    -- fits, else the original; the hook then replaces it.
    -- (Already a hooked output, or the plain original: it skips the hook.)
    local prev = last[src.path]
    on_text(copy((prev and prev.n == #lines) and prev.out or lines), false)
    if do_run then
      local function run_hook()
        if is_stale() then
          return
        end
        deliver(lines, true)
      end
      if debounced then
        local timer = (vim.uv or vim.loop).new_timer()
        if timer then
          room.timer = timer
          timer:start(
            M.debounce_ms(),
            0,
            vim.schedule_wrap(function()
              cancel_room(room)
              run_hook()
            end)
          )
        end
      else
        run_hook()
      end
    end
    return true
  end

  ---@type string[]
  local current = copy(lines)

  local function patch_flush()
    room.patch_pending = false
    if not is_stale() then
      deliver(copy(current), false)
    end
  end

  local function full_run()
    if is_stale() then
      return
    end
    local info = M.engine_info()
    set_status({ state = "translating", lang = lang, engine = info.engine, done = 0, total = nil })
    local opts = {
      target = lang,
      source = browser_cfg().display_lang_source,
      engine = browser_cfg().display_lang_engine,
      token = {
        generation = gen,
        current = function()
          return room.gen
        end,
      },
      on_unit = function(ev)
        if is_stale() or type(ev) ~= "table" then
          return
        end
        local first, lastl, got = ev.first, ev.last, ev.lines
        if
          type(first) ~= "number"
          or type(lastl) ~= "number"
          or first < 1
          or lastl > #current
          or lastl < first
          or not valid_lines(got, lastl - first + 1)
        then
          return -- a malformed patch is skipped; the final result still decides
        end
        for i = first, lastl do
          current[i] = got[i - first + 1]
        end
        status.done, status.total = ev.done, ev.total
        if not room.patch_pending then
          room.patch_pending = true
          vim.defer_fn(patch_flush, PATCH_MS)
        end
        push_status(false)
      end,
    }
    local handle = lib.translate_markdown(copy(lines), opts, function(ok, res, rinfo)
      if is_stale() then
        return
      end
      room.handle = nil
      if not ok then
        if res == "stale" or res == "cancelled" then
          return
        end
        fail(tostring(res))
        return
      end
      if not valid_lines(res, #lines) then
        fail(
          "the translation did not keep the line count ("
            .. tostring(type(res) == "table" and #res or res)
            .. " for "
            .. #lines
            .. ")"
        )
        return
      end
      local failed = type(rinfo) == "table" and tonumber(rinfo.failed) or 0
      if failed and failed > 0 then
        local first_err = type(rinfo.errors) == "table" and rinfo.errors[1] or nil
        report_once(
          ("display_lang: %d paragraph(s) could not be translated and stay original%s"):format(
            failed,
            first_err and (" (" .. tostring(first_err) .. ")") or ""
          )
        )
      end
      set_status({
        state = "done",
        lang = lang,
        engine = info.engine,
        message = failed > 0 and "partly original" or nil,
      })
      deliver(res, true)
    end)
    -- The callback never runs before translate_markdown has returned.
    room.handle = handle
  end

  -- Step 1: a valid text at once, from the cache only (nothing leaves the machine).
  local pre = lib.translate_markdown(copy(lines), {
    target = lang,
    source = browser_cfg().display_lang_source,
    engine = browser_cfg().display_lang_engine,
    cache_only = true,
  }, function(ok, res)
    if is_stale() then
      return
    end
    room.handle = nil
    if ok and valid_lines(res, #lines) then
      current = copy(res)
    else
      current = copy(lines)
    end
    deliver(copy(current), false)
    if not do_run then
      set_status({ state = "idle", lang = lang, message = "waiting for " .. M.trigger() })
      return
    end
    if debounced then
      set_status({ state = "idle", lang = lang, message = "waiting for a pause" })
      local timer = (vim.uv or vim.loop).new_timer()
      if not timer then
        full_run()
        return
      end
      room.timer = timer
      timer:start(
        M.debounce_ms(),
        0,
        vim.schedule_wrap(function()
          cancel_room(room)
          full_run()
        end)
      )
    else
      full_run()
    end
  end)
  room.handle = pre
  return true
end

--- A text-field edit from the browser was dropped because the preview shows a
--- transformed text. Said once.
---@return nil
function M.note_field_ignored()
  report_once(
    "text-field sync is off while the preview shows a transformed text (display_lang / browser.transform): "
      .. "the edit in the browser was not written to the buffer",
    vim.log.levels.INFO
  )
end

--- Cancel what is in flight for every room without forgetting the notices
--- (the option changed, the result of the old setting must not arrive).
---@return nil
function M.cancel_all()
  for _, r in pairs(rooms) do
    r.gen = r.gen + 1
    cancel_room(r)
  end
  last = {}
end

--- Switch the display language at runtime. `nil` turns it off.
---@param code string|nil
---@return boolean ok, string|nil err
function M.set_lang(code)
  if code ~= nil and (type(code) ~= "string" or not code:match("^%a[%w_%-]*$") or #code > 16) then
    return false, "not a language code: " .. tostring(code)
  end
  M.cancel_all()
  reported = {}
  browser_cfg().display_lang = code
  if code == nil then
    status = { state = "off" }
    push_status(true)
    privacy_noted = false
  else
    status = { state = "idle", lang = code }
  end
  return true, nil
end

return M

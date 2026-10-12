---@module 'mdview.adapter.inbound_poll'
-- Browser->Neovim polling bridge for the features that need to push events
-- upstream (Neovim has no WebSocket client, and the relay stays a dumb
-- byte-forwarder). While a session is active it polls, per tick:
--   * GET /nav        (experimental.click_navigate)   — clicked links to open
--   * GET /scrollback (experimental.reverse_scroll)   — browser scroll position
--   * GET /toggle     (sync_checkboxes, default on)   — task-list checkbox ticks
--   * GET /field      (sync_fields, default on)       — text-field write-back
--   * GET /edit       (edit_blocks, default off)      — block edits (source lines)
-- Only the enabled endpoints are polled; the timer runs only if at least one is
-- enabled. curl is already a hard dependency, and every polled event is
-- latency-tolerant enough for a poll.

local uv = vim.uv or vim.loop

local notify = require("lib.nvim.notify").create("").notify

local M = {}

--- How often the browser is polled for inbound events (checkbox ticks, field
--- edits, click-to-navigate). `transport.inbound_poll_ms`: every tick is a
--- request, so this is latency against traffic.
---@return integer
local function interval_ms()
  local ok, config = pcall(require, "mdview.config")
  if not ok then
    return 250
  end
  -- mdview.config exposes the live, merged values as `defaults`; there is no
  -- get()/options accessor.
  local t = type(config.defaults) == "table" and config.defaults.transport or nil
  local n = type(t) == "table" and t.inbound_poll_ms or nil
  return (type(n) == "number" and n > 0) and n or 250
end
local timer = nil
local nav_inflight = false
local scroll_inflight = false
local toggle_inflight = false
local field_inflight = false
local edit_inflight = false

---@internal
---@param endpoint string
---@return string
local function url_for(endpoint)
  local port = vim.g.mdview_server_port or 43219
  local token = require("mdview.core.state").get_token() or ""
  return string.format("http://localhost:%d/%s?token=%s", port, endpoint, vim.uri_encode(token))
end

---@internal
---@return table
local function experimental()
  return require("mdview.config").defaults.experimental or {}
end

-- ---- click-to-navigate -----------------------------------------------------

-- Absolute path? (Unix "/…" or Windows "C:/…" / "C:\…"). Back/forward
-- navigation sends absolute document paths; relative links are resolved against
-- the source document's directory.
---@internal
---@param p string
---@return boolean
local function is_absolute(p)
  return p:match("^/") ~= nil or p:match("^%a:[/\\]") ~= nil
end

---@internal
---@param key string
---@param href string
---@return nil
local function handle_nav(key, href)
  if type(key) ~= "string" or type(href) ~= "string" or href == "" then
    return
  end
  local target
  if is_absolute(href) then
    target = href
  else
    local dir = vim.fn.fnamemodify(key, ":h")
    target = vim.fn.simplify(dir .. "/" .. href)
  end
  local norm = require("mdview.helper.normalize").path(target)
  if norm then
    target = norm
  end
  if vim.fn.filereadable(target) ~= 1 then
    notify("[mdview] click-navigate: file not found: " .. target, vim.log.levels.WARN)
    return
  end
  pcall(vim.cmd.edit, vim.fn.fnameescape(target))
end

---@internal
---@return nil
local function poll_nav()
  if nav_inflight then
    return
  end
  nav_inflight = true
  vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", url_for("nav") }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      local body = vim.trim(table.concat(data, "\n"))
      if body == "" or body == "null" then
        return
      end
      local ok, arr = pcall(vim.json.decode, body)
      if not ok or type(arr) ~= "table" then
        return
      end
      vim.schedule(function()
        for _, r in ipairs(arr) do
          if type(r) == "table" then
            handle_nav(r.key, r.href)
          end
        end
      end)
    end,
    on_exit = function()
      nav_inflight = false
    end,
  })
end

-- ---- reverse scroll (browser -> nvim) --------------------------------------

-- Find the loaded buffer whose (normalized) name matches `key`.
---@internal
---@param key string
---@return integer|nil
local function buf_for_key(key)
  local normalize = require("mdview.helper.normalize")
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local name = normalize.path(vim.api.nvim_buf_get_name(b))
      if name == key then
        return b
      end
    end
  end
  return nil
end

-- The buffer a browser write-back (checkbox, text field, block edit) belongs
-- to: the one of the document Neovim last put into the room of the tab.
--
-- `key` is the room of the tab. With `browser.behavior = "reuse"` that is the
-- path of the FIRST document for the whole session, while the tab follows the
-- active buffer; so the room says nothing about which document is on screen.
-- Neovim knows (it pushed it: `live_push.shown_document`, kept up to date by
-- content pushes and buffer switches), and that is what is edited: not what the
-- request claims, which a tab that reloaded does not know at all and a stale one
-- gets wrong. A request that names a different document than the room holds is
-- refused (the tab is behind); a room Neovim never pushed a document into is not
-- a room of this session.
--
-- Only buffers mdview itself previews qualify: the token that reaches this
-- module belongs to the relay, it is not a licence to rewrite any loaded buffer.
---@internal
---@param key string # the room of the tab
---@param doc string|nil # the document the tab says it shows
---@return integer|nil buf
---@return string|nil reason # why there is none, in words for the person at the tab
local function target_buffer(key, doc)
  local shown = require("mdview.bindings.autocmds.live_push").shown_document(key)
  if not shown then
    return nil, "the preview is not showing a document from this session"
  end
  if type(doc) == "string" and doc ~= "" and doc ~= shown then
    return nil, "the document on screen changed"
  end
  local buf = buf_for_key(shown)
  if not buf or not vim.api.nvim_buf_is_loaded(buf) then
    return nil, "the document is not loaded"
  end
  if not require("mdview.helper.previewable").is(buf) then
    return nil, "the document is not one mdview previews"
  end
  return buf
end

-- Tell the person at the tab (room `key`) why a write-back was not applied.
-- A no-op without a running session.
---@internal
---@param key string
---@param message string
---@return nil
local function tell_tab(key, message)
  pcall(require("mdview.adapter.control").send, { notice = "Not saved: " .. message }, key)
end

-- Run `fn` when the user is not typing in `buf`. A change made to the buffer
-- while its owner is in Insert (or Replace) mode there is joined into the undo
-- block of what they type, so one `u` would take back their words and the
-- browser's edit together. Waits briefly (up to ~5 s), then applies anyway: a
-- user who stays in insert mode must not hold the browser's edit forever.
-- `fn` re-checks everything it relies on, as the buffer may have changed.
---@internal
---@param buf integer
---@param fn fun()
---@param tries integer|nil
---@return nil
local function when_not_inserting(buf, fn, tries)
  tries = tries or 0
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  local typing = (mode == "i" or mode == "R") and vim.api.nvim_get_current_buf() == buf
  if typing and tries < 20 then
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then
        when_not_inserting(buf, fn, tries + 1)
      end
    end, 250)
    return
  end
  if vim.api.nvim_buf_is_valid(buf) then
    fn()
  end
end

---@internal
---@param key string
---@param ratio number
---@return nil
local function handle_scroll(key, ratio)
  if type(key) ~= "string" or type(ratio) ~= "number" then
    return
  end
  local buf = buf_for_key(key)
  if not buf then
    return
  end
  -- Only move the cursor in a window actually showing that buffer.
  local win
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      win = w
      break
    end
  end
  if not win then
    return
  end
  local total = vim.api.nvim_buf_line_count(buf)
  local line = math.floor(ratio * (total - 1) + 0.5) + 1
  if line < 1 then
    line = 1
  elseif line > total then
    line = total
  end
  -- Suppress the outgoing ping this cursor move would otherwise trigger.
  require("mdview.bindings.autocmds.scroll_sync").suppress(250)
  pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
end

---@internal
---@return nil
local function poll_scroll()
  if scroll_inflight then
    return
  end
  scroll_inflight = true
  vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", url_for("scrollback") }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      local body = vim.trim(table.concat(data, "\n"))
      if body == "" or body == "null" then
        return
      end
      local ok, obj = pcall(vim.json.decode, body)
      if not ok or type(obj) ~= "table" or obj.key == nil then
        return
      end
      vim.schedule(function()
        handle_scroll(obj.key, obj.ratio)
      end)
    end,
    on_exit = function()
      scroll_inflight = false
    end,
  })
end

-- ---- task-list checkbox toggle (browser -> nvim buffer) --------------------

-- Flip the GFM task-list checkbox on 1-based `line` of the buffer showing the
-- document of the tab to `checked`, then push the change so the preview
-- reflects it. Standalone mode never reaches here (the relay edits the file
-- itself); this is the :MDView start path, where the buffer — possibly with
-- unsaved edits — is the source of truth the relay must not touch.
--
-- `expected` is the text of that line as the browser rendered it: another
-- write-back that arrived first (a text field that gained lines, a block edit)
-- may have moved the lines, and the tick must not land on the neighbour. A
-- line that no longer holds a task marker is left alone as well.
---@internal
---@param key string # the room of the tab
---@param line integer
---@param checked boolean
---@param doc string|nil # the document the tab says it shows (see `target_buffer`)
---@param expected string|nil
---@return nil
local function handle_toggle(key, line, checked, doc, expected)
  if type(key) ~= "string" or type(line) ~= "number" or line < 1 or line ~= math.floor(line) then
    return
  end
  local buf = target_buffer(key, doc)
  if not buf then
    return
  end
  when_not_inserting(buf, function()
    if vim.bo[buf].modifiable ~= true then
      notify("[mdview] preview checkbox dropped: the buffer is not modifiable", vim.log.levels.WARN)
      return
    end
    if line > vim.api.nvim_buf_line_count(buf) then
      return
    end
    local raw = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
    if not raw then
      return
    end
    -- A buffer loaded with 'fileformat' unix from a CRLF file keeps a "\r".
    local cur, cr = raw:gsub("\r$", "")
    if type(expected) == "string" and expected ~= "" and cur ~= (expected:gsub("\r$", "")) then
      return -- the lines moved since the render: not the checkbox that was ticked
    end
    local pre, state, post = cur:match("^(%s*[-*+] %[)([ xX])(%].*)$")
    if not pre then
      return -- not a checkbox line; don't corrupt it
    end
    local want = checked and "x" or " "
    if state == want then
      return -- already in the requested state
    end
    local ok =
      pcall(vim.api.nvim_buf_set_lines, buf, line - 1, line, false, { pre .. want .. post .. (cr > 0 and "\r" or "") })
    if not ok then
      return
    end
    -- Neovim fires TextChanged for a change of the current buffer only; push
    -- explicitly so a buffer shown elsewhere is updated in the preview as well.
    pcall(require("mdview.bindings.autocmds.live_push").push_buffer_changes, buf, { full = true })
  end)
end

---@internal
---@return nil
local function poll_toggle()
  if toggle_inflight then
    return
  end
  toggle_inflight = true
  vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", url_for("toggle") }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      local body = vim.trim(table.concat(data, "\n"))
      if body == "" or body == "null" then
        return
      end
      local ok, arr = pcall(vim.json.decode, body)
      if not ok or type(arr) ~= "table" then
        return
      end
      vim.schedule(function()
        for _, r in ipairs(arr) do
          if type(r) == "table" then
            pcall(handle_toggle, r.key, r.line, r.checked, r.doc, r.expected)
          end
        end
      end)
    end,
    on_exit = function()
      toggle_inflight = false
    end,
  })
end

-- ---- text field write-back (browser -> nvim buffer) ------------------------

local escape_attr, escape_text
do
  -- HTML-escape for a double-quoted attribute value / element text, mirroring
  -- native/server/internal/source/field.go so start mode and standalone write
  -- byte-identical output.
  local function replace(s, from, to)
    return (s:gsub(from, to))
  end
  escape_attr = function(v)
    v = replace(v, "&", "&amp;")
    v = replace(v, "<", "&lt;")
    v = replace(v, ">", "&gt;")
    v = replace(v, '"', "&quot;")
    return v
  end
  escape_text = function(v)
    v = replace(v, "&", "&amp;")
    v = replace(v, "<", "&lt;")
    v = replace(v, ">", "&gt;")
    return v
  end
end

-- Make the buffer hold `new_text` and push the result. Used for field edits,
-- which can change content across lines (a multi-line textarea body); a
-- single-line set like handle_toggle's isn't enough.
--
-- Only the lines that differ are replaced: the lines before and after the change
-- are left alone, so their marks, folds and extmarks survive (replacing the whole
-- buffer moves every one of them to the top).
---@internal
---@param buf integer
---@param new_text string
---@param old string[] # the buffer's lines the text was derived from
---@return nil
local function apply_buffer_text(buf, new_text, old)
  local new = vim.split(new_text, "\n", { plain = true })

  local first = 1
  while first <= #old and first <= #new and old[first] == new[first] do
    first = first + 1
  end
  local old_last, new_last = #old, #new
  while old_last >= first and new_last >= first and old[old_last] == new[new_last] do
    old_last = old_last - 1
    new_last = new_last - 1
  end
  if first > old_last and first > new_last then
    return -- nothing differs
  end

  local ok, err =
    pcall(vim.api.nvim_buf_set_lines, buf, first - 1, old_last, false, vim.list_slice(new, first, new_last))
  if not ok then
    notify("[mdview] preview edit dropped: " .. tostring(err), vim.log.levels.WARN)
    return
  end
  pcall(require("mdview.bindings.autocmds.live_push").push_buffer_changes, buf, { full = true })
end

-- Set the syncable field named `name` in the buffer showing `key` to `value`,
-- then push. Located by the `name` attribute (raw HTML has no source position),
-- like the Go side. Standalone never reaches here (the relay edits the file).
---@internal
---@param key string
---@param name string
---@param value string
---@param doc string|nil # the document the tab is showing (see `target_buffer`)
---@return nil
local function handle_field(key, name, value, doc)
  if type(key) ~= "string" or type(name) ~= "string" or name == "" or type(value) ~= "string" then
    return
  end
  -- The preview shows a transformed text (a display language, browser.transform):
  -- what the browser sends back belongs to that text, not to the buffer's, so
  -- writing it into the buffer is off. The checkbox path stays: it reads the
  -- real line and only flips its marker.
  if require("mdview.core.display").active() then
    require("mdview.core.display").note_field_ignored()
    return
  end
  local buf = target_buffer(key, doc)
  if not buf then
    return
  end
  when_not_inserting(buf, function()
    if vim.bo[buf].modifiable ~= true then
      notify("[mdview] preview edit dropped: the buffer is not modifiable", vim.log.levels.WARN)
      return
    end
    local old_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(old_lines, "\n")
    local q = vim.pesc(name)

    -- textarea first (explicit close, unambiguous body). `.` in Lua patterns
    -- matches newlines, so a multi-line body is handled. `%s` before `name=`: a
    -- boundary, so `data-name="x"` is not the field called `x`.
    local ta_open, ta_body_start = text:find('<textarea[^>]*%sname="' .. q .. '"[^>]*>')
    if ta_open then
      local close_start = text:find("</textarea>", ta_body_start + 1, true)
      if close_start then
        local new_text = text:sub(1, ta_body_start) .. escape_text(value) .. text:sub(close_start)
        apply_buffer_text(buf, new_text, old_lines)
        return
      end
    end

    -- input: find the tag by name, then set/insert its value attribute.
    local in_start, in_end = text:find('<input[^>]*%sname="' .. q .. '"[^>]*>')
    if in_start then
      local tag = text:sub(in_start, in_end)
      local repl = 'value="' .. escape_attr(value) .. '"'
      local new_tag
      if tag:find('value="[^"]*"') then
        new_tag = (tag:gsub('value="[^"]*"', function()
          return repl
        end, 1))
      elseif tag:sub(-2) == "/>" then
        new_tag = tag:sub(1, -3):gsub("%s+$", "") .. " " .. repl .. "/>"
      else
        new_tag = tag:sub(1, -2):gsub("%s+$", "") .. " " .. repl .. ">"
      end
      local new_text = text:sub(1, in_start - 1) .. new_tag .. text:sub(in_end + 1)
      apply_buffer_text(buf, new_text, old_lines)
    end
  end)
end

---@internal
---@return nil
local function poll_field()
  if field_inflight then
    return
  end
  field_inflight = true
  vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", url_for("field") }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      local body = vim.trim(table.concat(data, "\n"))
      if body == "" or body == "null" then
        return
      end
      local ok, arr = pcall(vim.json.decode, body)
      if not ok or type(arr) ~= "table" then
        return
      end
      vim.schedule(function()
        for _, r in ipairs(arr) do
          if type(r) == "table" then
            pcall(handle_field, r.key, r.name, r.value, r.doc)
          end
        end
      end)
    end,
    on_exit = function()
      field_inflight = false
    end,
  })
end

-- ---- lifecycle -------------------------------------------------------------

-- ---- block edit (browser -> nvim buffer) -----------------------------------

-- Is `n` a whole number a buffer line can be?
---@internal
---@param n any
---@return boolean
local function is_line_number(n)
  return type(n) == "number" and n == math.floor(n) and n >= 1 and n < 2 ^ 31
end

-- Replace the 1-based, inclusive buffer lines start..end_ of the buffer showing
-- the document of the tab (see `target_buffer`) with `text`, but only while
-- those lines are still `expected`: the edit was made against the text the
-- preview was rendered from, and a buffer that moved on since must not be
-- overwritten by it. Standalone never reaches here (the relay edits the file).
-- Only the one range is replaced, so marks, folds and the rest of the undo
-- history stay put, and `u` takes the edit back as one step.
--
-- A buffer whose lines carry a "\r" (a CRLF file loaded with 'fileformat' unix)
-- is compared without it, and the new lines get the ending of the lines they
-- replace; the browser never sees the "\r".
--
-- Every refusal is reported to the tab (`notice`), because to the person
-- editing the block would otherwise just lose their text.
---@internal
---@param key string # the room of the tab
---@param start integer
---@param end_ integer
---@param expected string
---@param text string
---@param doc string|nil # the document the tab says it shows
---@return nil
local function handle_edit(key, start, end_, expected, text, doc)
  if type(key) ~= "string" or type(expected) ~= "string" or type(text) ~= "string" then
    return
  end
  if not is_line_number(start) or not is_line_number(end_) or end_ < start then
    return
  end
  -- Switched off since the edit was queued (`:MDView edit off`): said so by the
  -- command itself.
  if require("mdview.config").defaults.edit_blocks ~= true then
    return
  end
  -- The preview shows a transformed text (browser.transform / a display
  -- language): the lines it sent back belong to that text, not the buffer's.
  if require("mdview.core.display").active() then
    notify("[mdview] preview edit dropped: the preview shows a translation, not the buffer", vim.log.levels.INFO)
    tell_tab(key, "the preview shows a translation, not the file")
    return
  end
  local buf, why = target_buffer(key, doc)
  if not buf then
    notify("[mdview] preview edit dropped: " .. tostring(why), vim.log.levels.WARN)
    tell_tab(key, tostring(why))
    return
  end

  -- Say that the edit was not applied, and put the buffer's real text back
  -- into the tab.
  local function refuse(message)
    notify("[mdview] preview edit dropped: " .. message, vim.log.levels.WARN)
    tell_tab(key, message)
    pcall(require("mdview.bindings.autocmds.live_push").push_buffer_changes, buf, { full = true })
  end

  when_not_inserting(buf, function()
    if vim.bo[buf].modifiable ~= true then
      refuse("the buffer is not modifiable")
      return
    end
    if end_ > vim.api.nvim_buf_line_count(buf) then
      refuse("the lines changed in the buffer")
      return
    end

    local old = vim.api.nvim_buf_get_lines(buf, start - 1, end_, false)
    local shown = {}
    for i, l in ipairs(old) do
      shown[i] = (l:gsub("\r$", ""))
    end
    if table.concat(shown, "\n") ~= (expected:gsub("\r\n", "\n")) then
      refuse("the lines changed in the buffer")
      return
    end

    local lines = vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
    if old[1]:sub(-1) == "\r" then
      local last_cr = old[#old]:sub(-1) == "\r"
      for i = 1, #lines do
        if i < #lines or last_cr then
          lines[i] = lines[i] .. "\r"
        end
      end
    end

    local ok, err = pcall(vim.api.nvim_buf_set_lines, buf, start - 1, end_, false, lines)
    if not ok then
      refuse(tostring(err))
      return
    end
    -- Neovim fires TextChanged for a change of the current buffer only; push
    -- explicitly so a buffer shown elsewhere is updated in the preview as well.
    pcall(require("mdview.bindings.autocmds.live_push").push_buffer_changes, buf, { full = true })
  end)
end

---@internal
---@return nil
local function poll_edit()
  if edit_inflight then
    return
  end
  edit_inflight = true
  vim.fn.jobstart({ "curl", "-sS", "--max-time", "2", url_for("edit") }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      local body = vim.trim(table.concat(data, "\n"))
      if body == "" or body == "null" then
        return
      end
      local ok, arr = pcall(vim.json.decode, body)
      if not ok or type(arr) ~= "table" then
        return
      end
      vim.schedule(function()
        for _, r in ipairs(arr) do
          if type(r) == "table" then
            pcall(handle_edit, r.key, r.start, r["end"], r.expected, r.text, r.doc)
          end
        end
      end)
    end,
    on_exit = function()
      edit_inflight = false
    end,
  })
end

---@internal
---@return nil
local function tick()
  if not require("mdview.core.state").get_server() then
    return
  end
  if vim.fn.executable("curl") ~= 1 then
    return
  end
  local exp = experimental()
  if exp.click_navigate == true then
    poll_nav()
  end
  if exp.reverse_scroll == true then
    poll_scroll()
  end
  local cfg = require("mdview.config").defaults
  if cfg.sync_checkboxes ~= false then
    poll_toggle()
  end
  if cfg.sync_fields ~= false then
    poll_field()
  end
  if cfg.edit_blocks == true then
    poll_edit()
  end
end

--- Start polling. No-op unless at least one inbound feature is enabled.
--- Safe to call repeatedly.
---@return nil
function M.start()
  if timer then
    return
  end
  local exp = experimental()
  local cfg = require("mdview.config").defaults
  local sync = cfg.sync_checkboxes ~= false or cfg.sync_fields ~= false or cfg.edit_blocks == true
  if not (exp.click_navigate == true or exp.reverse_scroll == true or sync) then
    return
  end
  timer = uv.new_timer()
  if not timer then
    return
  end
  local interval = interval_ms()
  timer:start(interval, interval, vim.schedule_wrap(tick))
end

--- Stop polling. Safe to call when not started.
---@return nil
function M.stop()
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    timer = nil
  end
  nav_inflight = false
  scroll_inflight = false
  toggle_inflight = false
  field_inflight = false
  edit_inflight = false
end

-- Exposed for headless tests.
M._handle_nav = handle_nav
M._handle_scroll = handle_scroll
M._handle_toggle = handle_toggle
M._handle_field = handle_field
M._handle_edit = handle_edit

return M

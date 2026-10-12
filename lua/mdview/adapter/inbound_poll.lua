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

-- Report a failure of a request handler (it is never silent) and carry on.
---@internal
---@param what string
---@param fn function
---@param ... any
---@return nil
local function safe(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    notify(("[mdview] preview %s failed: %s"):format(what, tostring(err)), vim.log.levels.ERROR)
  end
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
    -- Relative to the document on screen: the room is the first document of the
    -- session under "reuse".
    local base = require("mdview.bindings.autocmds.live_push").shown_document(key) or key
    local dir = vim.fn.fnamemodify(base, ":h")
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
            safe("navigation", handle_nav, r.key, r.href)
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
    -- The tab is behind: its document ping got lost (the relay does not replay
    -- it to a tab that connected later). Say again what is shown, so a retry
    -- by the person is not refused the same way for ever.
    pcall(require("mdview.adapter.ws_client").send_doc, key, shown)
    return nil, "the document on screen changed; try again"
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

-- Time of the user's last keystroke (`vim.uv.now()` ms), for `when_not_inserting`.
local TYPING_WINDOW_MS = 1000
local last_key_ms = 0
---@type table<integer, boolean>
local wait_said = {} -- per buffer: the "waits until you stop typing" notice is shown once per wait
vim.on_key(function()
  last_key_ms = vim.uv.now()
end, vim.api.nvim_create_namespace("mdview_inbound_keys"))

-- Run `fn` when the user is not typing in `buf`. A change made to the buffer
-- while its owner is in Insert (or Replace) mode there is joined into the undo
-- block of what they type, so one `u` would take back their words and the
-- browser's edit together. "Typing" means a key in the last second, not merely
-- standing in insert mode: the edit waits only for real typing (up to ~5 s, and
-- says so once), then applies anyway. When it applies in insert mode, the undo
-- block is cut before and after it, so `u` takes back the browser's edit alone.
-- `fn` re-checks everything it relies on, as the buffer may have changed.
-- `on_gone` is called instead of `fn` when the buffer is deleted while waiting.
---@internal
---@param buf integer
---@param fn fun()
---@param on_gone fun()|nil
---@param tries integer|nil
---@return nil
local function when_not_inserting(buf, fn, on_gone, tries)
  tries = tries or 0
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  local inserting = (mode == "i" or mode == "R") and vim.api.nvim_get_current_buf() == buf
  local typing = inserting and (vim.uv.now() - last_key_ms) < TYPING_WINDOW_MS
  if typing and tries < 20 then
    if not wait_said[buf] then
      wait_said[buf] = true
      notify("[mdview] a change from the preview waits until you stop typing", vim.log.levels.INFO)
    end
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then
        when_not_inserting(buf, fn, on_gone, tries + 1)
      else
        wait_said[buf] = nil
        if on_gone then
          on_gone()
        end
      end
    end, 250)
    return
  end
  wait_said[buf] = nil
  if not vim.api.nvim_buf_is_valid(buf) then
    if on_gone then
      on_gone()
    end
    return
  end
  if inserting then
    -- `:let &undolevels = &undolevels` starts a new undo block (:help undo-blocks)
    vim.cmd("let &undolevels = &undolevels")
    local ok, err = pcall(fn)
    vim.cmd("let &undolevels = &undolevels")
    if not ok then
      error(err, 0)
    end
    return
  end
  fn()
end

-- The same for a request that found no buffer to apply to.
---@internal
---@param key string
---@param what string
---@param why string|nil
---@return nil
local function refuse_no_buffer(key, what, why)
  notify(("[mdview] %s dropped: %s"):format(what, tostring(why)), vim.log.levels.WARN)
  tell_tab(key, tostring(why))
end

-- Per-buffer FIFO of the changes the browser asked for. Each one waits for the
-- user to stop typing (`when_not_inserting`), and a later one must not overtake
-- an earlier one that is still waiting: field "first" in Insert mode, Esc, field
-- "second" has to end with "second". `queues[buf]` is the live queue of a
-- buffer; `M.stop` drops them all, and a closure of a dropped queue does nothing.
---@type table<integer, { items: { req: table, fn: fun() }[], active: boolean }>
local queues = {}

-- Run `fn` for `buf` after the changes queued before it, once the user is not
-- typing there. An error in `fn` is reported and does not stop the queue.
---@internal
---@param buf integer
---@param req { key: string, doc: string|nil, what: string } # whose request it is
---@param fn fun()
---@return nil
local function enqueue(buf, req, fn)
  local q = queues[buf]
  if not q then
    q = { items = {}, active = false }
    queues[buf] = q
  end
  q.items[#q.items + 1] = { req = req, fn = fn }
  if q.active then
    return
  end
  q.active = true
  -- Give up on the queue: every change still in it is reported, none vanishes.
  local function abandon(reason)
    if queues[buf] == q then
      queues[buf] = nil
    end
    for _, item in ipairs(q.items) do
      refuse_no_buffer(item.req.key, item.req.what, reason)
    end
    q.items = {}
  end
  local function step()
    if queues[buf] ~= q then
      return -- stopped meanwhile
    end
    local nxt = table.remove(q.items, 1)
    if not nxt then
      queues[buf] = nil
      return
    end
    if not vim.api.nvim_buf_is_valid(buf) then
      refuse_no_buffer(nxt.req.key, nxt.req.what, "the buffer is gone")
      abandon("the buffer is gone")
      return
    end
    local ok, err = pcall(when_not_inserting, buf, function()
      if queues[buf] ~= q then
        return
      end
      -- It may have waited for seconds, behind others: is this still the buffer
      -- the tab's document maps to (a buffer switch under "reuse")? Whatever
      -- happens here, the next change gets its turn.
      local ran, why = pcall(function()
        local now, reason = target_buffer(nxt.req.key, nxt.req.doc)
        if now ~= buf then
          refuse_no_buffer(nxt.req.key, nxt.req.what, reason or "the document on screen changed; try again")
        else
          safe("change", nxt.fn)
        end
      end)
      if not ran then
        notify(("[mdview] preview change failed: %s"):format(tostring(why)), vim.log.levels.ERROR)
      end
      step()
    end, function()
      -- deleted while the change waited for the user to stop typing
      if queues[buf] == q then
        refuse_no_buffer(nxt.req.key, nxt.req.what, "the buffer is gone")
        abandon("the buffer is gone")
      end
    end)
    if not ok then
      notify(("[mdview] preview change failed: %s"):format(tostring(err)), vim.log.levels.ERROR)
      refuse_no_buffer(nxt.req.key, nxt.req.what, "it could not be applied")
      abandon("an earlier change could not be applied")
    end
  end
  step()
end

-- The buffer text changed for a request of the tab in room `key`: push it so
-- every view shows it. The push goes to the room Neovim currently feeds; a tab
-- of an older room (after a second :MDView open) is brought up to date as well.
---@internal
---@param buf integer
---@param key string
---@return nil
local function push_result(buf, key)
  local live = require("mdview.bindings.autocmds.live_push")
  pcall(live.push_buffer_changes, buf, { full = true })
  if require("mdview.helper.target_key").resolve(buf) ~= key then
    pcall(live.push_buffer_changes, buf, { full = true, room = key })
  end
end

-- A change from the preview was not applied: say so in Neovim and in the tab,
-- and put the buffer's real text back into the tab, so a checkbox or field it
-- changed on its own goes back to what the buffer says.
---@internal
---@param key string # the room of the tab
---@param buf integer
---@param what string # "preview edit" | "preview checkbox"
---@param message string
---@return nil
local function refuse(key, buf, what, message)
  notify(("[mdview] %s dropped: %s"):format(what, message), vim.log.levels.WARN)
  tell_tab(key, message)
  push_result(buf, key)
end

---@internal
---@param key string
---@param ratio number
---@return nil
local function handle_scroll(key, ratio)
  if type(key) ~= "string" or type(ratio) ~= "number" then
    return
  end
  -- The room is not the document under "reuse": scroll the shown one.
  local buf = buf_for_key(require("mdview.bindings.autocmds.live_push").shown_document(key) or key)
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

-- The line with its task marker state neutralised ("[ ]", "[x]", "[X]" alike):
-- a double click sends tick and untick against the same rendered text.
---@internal
---@param s string
---@return string
local function neutral_marker(s)
  local pre, post = s:match("^(%s*[-*+] %[)[ xX](%].*)$")
  if pre then
    return pre .. " " .. post
  end
  return s
end

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
  local buf, why = target_buffer(key, doc)
  if not buf then
    refuse_no_buffer(key, "preview checkbox", why)
    return
  end
  local what = "preview checkbox"
  enqueue(buf, { key = key, doc = doc, what = what }, function()
    if vim.bo[buf].modifiable ~= true then
      refuse(key, buf, what, "the buffer is not modifiable")
      return
    end
    local raw = line <= vim.api.nvim_buf_line_count(buf) and vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
    if not raw then
      refuse(key, buf, what, "the lines changed in the buffer")
      return
    end
    -- A buffer loaded with 'fileformat' unix from a CRLF file keeps a "\r".
    local cur, cr = raw:gsub("\r$", "")
    if type(expected) == "string" and expected ~= "" then
      local want_line = expected:gsub("\r$", "")
      if not require("mdview.core.display").active() then
        if neutral_marker(cur) ~= neutral_marker(want_line) then
          -- the lines moved since the render: not the checkbox that was ticked
          refuse(key, buf, what, "the lines changed in the buffer")
          return
        end
      else
        -- Under a display language the browser rendered a translated text, so
        -- only the part a translation leaves alone can be compared: the indent
        -- and the bullet in front of the marker. (So equal neighbours cannot be
        -- told apart, and a transform that rewrites the bullet or the indent
        -- makes the tick be refused: the text it shows is not the buffer's.)
        local want_pre = want_line:match("^(%s*[-*+] %[)[ xX]%]")
        if want_pre and want_pre ~= cur:match("^(%s*[-*+] %[)") then
          refuse(key, buf, what, "the lines changed in the buffer")
          return
        end
      end
    end
    local pre, state, post = cur:match("^(%s*[-*+] %[)([ xX])(%].*)$")
    if not pre then
      -- not a checkbox line; don't corrupt it
      refuse(key, buf, what, "that line is no longer a checkbox")
      return
    end
    local want = checked and "x" or " "
    if state == want then
      return -- already in the requested state
    end
    local ok, err =
      pcall(vim.api.nvim_buf_set_lines, buf, line - 1, line, false, { pre .. want .. post .. (cr > 0 and "\r" or "") })
    if not ok then
      refuse(key, buf, what, tostring(err))
      return
    end
    -- Neovim fires TextChanged for a change of the current buffer only; push
    -- explicitly so a buffer shown elsewhere is updated in the preview as well.
    push_result(buf, key)
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
            safe("checkbox", handle_toggle, r.key, r.line, r.checked, r.doc, r.expected)
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
---@param key string # the room of the tab whose request this is
---@return nil
local function apply_buffer_text(buf, new_text, old, key)
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
    refuse(key, buf, "preview edit", tostring(err))
    return
  end
  push_result(buf, key)
end

-- Opening tags `<tagname ...>` of `text` as { start, end } byte positions. A
-- quoted attribute value may hold a `>`, so the end is the first `>` outside
-- quotes. Mirrors the tag expressions of native/server/internal/source/field.go.
---@internal
---@param text string
---@param tagname string
---@return integer[][]
local function opening_tags(text, tagname)
  local found = {}
  local open = "<" .. tagname
  local init = 1
  while true do
    local s = text:find(open, init, true)
    if not s then
      break
    end
    local after = text:sub(s + #open, s + #open)
    -- "<inputx" is not a tag of this name at all (the relay word boundary); "<input-x"
    -- is one tag of another name, skipped as a whole: what its quoted values
    -- hold is not a tag of ours.
    if not after:match("[%w_]") then
      local i, quote, e = s + #open, nil, nil
      while i <= #text do
        local c = text:sub(i, i)
        if quote then
          if c == quote then
            quote = nil
          end
        elseif c == '"' or c == "'" then
          quote = c
        elseif c == ">" then
          e = i
          break
        end
        i = i + 1
      end
      if e then
        if after == "" or after:match("[ \t\r\n\f/>]") then
          found[#found + 1] = { s, e }
        end
        init = e + 1
      else
        init = s + #open -- an unclosed quote: look at the next tag
      end
    else
      init = s + #open
    end
  end
  return found
end

-- The attributes of the tag `tag`, read after its first `from` bytes: name,
-- unquoted value, and where each sits (from its name to the end of its value).
---@internal
---@param tag string
---@param from integer
---@return { name: string, value: string, s: integer, e: integer }[]
local function tag_attributes(tag, from)
  local list = {}
  local pos = from + 1
  while pos <= #tag do
    -- White space is [ \t\r\n\f] as in the relay's \s: Lua's %s also takes \v.
    local _, ne, name = tag:find("^[ \t\r\n\f]+([^ \t\r\n\f\"'<>/=]+)", pos)
    if not ne then
      pos = pos + 1
    else
      local ns = ne - #name + 1
      local e, value = ne, ""
      local ve, v
      local q = tag:match("^[ \t\r\n\f]*=[ \t\r\n\f]*([\"'])", ne + 1)
      if q then
        _, ve, v = tag:find("^[ \t\r\n\f]*=[ \t\r\n\f]*" .. q .. "([^" .. q .. "]*)" .. q, ne + 1)
      else
        _, ve, v = tag:find("^[ \t\r\n\f]*=[ \t\r\n\f]*([^ \t\r\n\f\"'<>=`]+)", ne + 1)
      end
      if ve then
        e, value = ve, v
      else
        -- `value=` with nothing after it: the `=` still belongs to the attribute
        local _, eq = tag:find("^[ \t\r\n\f]*=[ \t\r\n\f]*", ne + 1)
        if eq then
          e = eq
        end
      end
      list[#list + 1] = { name = name:lower(), value = value, s = ns, e = e }
      pos = e + 1
    end
  end
  return list
end

-- Does the attribute called `name` of `tag` say `want`?
---@internal
---@param tag string
---@param from integer
---@param want string
---@return boolean
local function tag_has_name(tag, from, want)
  for _, a in ipairs(tag_attributes(tag, from)) do
    if a.name == "name" then
      return a.value == want
    end
  end
  return false
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
  local buf, why = target_buffer(key, doc)
  if not buf then
    refuse_no_buffer(key, "preview edit", why)
    return
  end
  enqueue(buf, { key = key, doc = doc, what = "preview edit" }, function()
    if vim.bo[buf].modifiable ~= true then
      refuse(key, buf, "preview edit", "the buffer is not modifiable")
      return
    end
    local old_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(old_lines, "\n")

    -- textarea first (explicit close, unambiguous body). The field is the tag
    -- whose attribute called exactly `name` says `name`: `data-name="x"` is not
    -- the field called `x`, and a `>` inside a quoted value does not end the tag.
    for _, pos in ipairs(opening_tags(text, "textarea")) do
      if tag_has_name(text:sub(pos[1], pos[2]), #"<textarea", name) then
        local close_start = text:find("</textarea>", pos[2] + 1, true)
        if close_start then
          local new_text = text:sub(1, pos[2]) .. escape_text(value) .. text:sub(close_start)
          apply_buffer_text(buf, new_text, old_lines, key)
          return
        end
      end
    end

    -- input: find the tag by name, then set/insert its value attribute.
    for _, pos in ipairs(opening_tags(text, "input")) do
      local tag = text:sub(pos[1], pos[2])
      if tag_has_name(tag, #"<input", name) then
        local repl = 'value="' .. escape_attr(value) .. '"'
        local new_tag
        for _, a in ipairs(tag_attributes(tag, #"<input")) do
          if a.name == "value" then
            new_tag = tag:sub(1, a.s - 1) .. repl .. tag:sub(a.e + 1)
            break
          end
        end
        if not new_tag then
          if tag:sub(-2) == "/>" then
            new_tag = tag:sub(1, -3):gsub("[ \t\r\n\f]+$", "") .. " " .. repl .. "/>"
          else
            new_tag = tag:sub(1, -2):gsub("[ \t\r\n\f]+$", "") .. " " .. repl .. ">"
          end
        end
        local new_text = text:sub(1, pos[1] - 1) .. new_tag .. text:sub(pos[2] + 1)
        apply_buffer_text(buf, new_text, old_lines, key)
        return
      end
    end
    refuse(key, buf, "preview edit", ("there is no text field named %s any more"):format(name))
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
            safe("field", handle_field, r.key, r.name, r.value, r.doc)
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
    refuse_no_buffer(key, "preview edit", why)
    return
  end

  local what = "preview edit"
  enqueue(buf, { key = key, doc = doc, what = what }, function()
    if vim.bo[buf].modifiable ~= true then
      refuse(key, buf, what, "the buffer is not modifiable")
      return
    end
    if end_ > vim.api.nvim_buf_line_count(buf) then
      refuse(key, buf, what, "the lines changed in the buffer")
      return
    end

    local old = vim.api.nvim_buf_get_lines(buf, start - 1, end_, false)
    local shown = {}
    for i, l in ipairs(old) do
      shown[i] = (l:gsub("\r$", ""))
    end
    -- The browser's `expected` has no "\r\n"; a CRLF block it read from a buffer
    -- loaded as unix can still end in a lone "\r" on its last line.
    local want = expected:gsub("\r\n", "\n"):gsub("\r$", "")
    if table.concat(shown, "\n") ~= want then
      refuse(key, buf, what, "the lines changed in the buffer")
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
      refuse(key, buf, what, tostring(err))
      return
    end
    -- Neovim fires TextChanged for a change of the current buffer only; push
    -- explicitly so a buffer shown elsewhere is updated in the preview as well.
    push_result(buf, key)
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
            safe("edit", handle_edit, r.key, r.start, r["end"], r.expected, r.text, r.doc)
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
  -- Changes still waiting for the user to stop typing belong to the session that
  -- ended: their closures see the queue is gone and do nothing.
  queues = {}
end

-- Exposed for headless tests.
M._handle_nav = handle_nav
M._handle_scroll = handle_scroll
M._handle_toggle = handle_toggle
M._handle_field = handle_field
M._handle_edit = handle_edit
M._when_not_inserting = when_not_inserting
-- test seam: pretend the last keystroke happened at `ms` (vim.uv.now() clock)
---@param ms integer
---@return nil
function M._set_last_key(ms)
  last_key_ms = ms
end

return M

---@module 'mdview.adapter.shared_relay'
--- One relay and one preview tab for every Neovim instance (`shared_relay.enabled`,
--- opt-in; docs/FEATURES/SHARED_RELAY.md).
---
--- The first `:MDView start` spawns the relay with `--shared` and detached from
--- this instance (it must outlive it); the relay writes port and token to the
--- discovery file. A later `:MDView start` in another instance finds the file,
--- checks the relay answers (`GET /attach`), adopts its port and token and
--- attaches instead of spawning: no second relay, no second tab.
---
--- Who the tab shows: the instance that pushed last owns the room (the relay
--- records it from `/update` and `/doc`), and only the owner pushes. An
--- instance takes the room over when it gains the focus (`FocusGained`, needs
--- focus reporting of the terminal) or, as the fallback for terminals without
--- it, on the first sign of activity in it (cursor moved, buffer entered,
--- insert mode). It learns that another instance took over from the heartbeat
--- (`GET /attach`, every `heartbeat_ms`), and then stops pushing.
---
--- Write-backs (checkbox, field, block edit, click-to-navigate, reverse scroll)
--- are drained per instance: each one names itself (`client=`) when it polls,
--- and the relay hands it the requests of the rooms it owns only. The same file
--- open in two instances therefore goes to the one whose document the tab shows,
--- i.e. the focused one.
---
--- Lifetime: every request naming a client is a heartbeat; `:MDView stop` and
--- quitting Neovim detach (`POST /detach`). The relay ends (closing the tab) once
--- no instance has been heard from for `idle_timeout_s`, or right after the
--- last one detached.

local uv = vim.uv or vim.loop
local notify = require("lib.nvim.notify").create("").notify

local M = {}

--- The shared-relay contract this plugin speaks; must match the relay's
--- relay.SharedProtocol (native/server/internal/relay/clients.go).
M.PROTOCOL = 1

--- This instance uses a shared relay (spawned it or attached to it).
M._attached = false
--- This instance believes it owns the tab's room (it pushed last).
M._owner = false
--- uv.now() of the last takeover: a heartbeat answer to a request sent before it
--- describes the room before this instance took it, and is ignored.
M._claimed_at = 0
--- The rooms with a connected tab, from the last /attach answer.
M._tabs = {}

local heartbeat_timer = nil
local heartbeat_inflight = false
local heartbeat_failures = 0
local heartbeat_ok_once = false

---@internal
---@return table
local function cfg()
  local c = require("mdview.config").defaults.shared_relay
  return type(c) == "table" and c or {}
end

--- Whether the shared relay is switched on in the config.
---@return boolean
function M.enabled()
  return cfg().enabled == true
end

--- Whether this instance's session runs against a shared relay.
---@return boolean
function M.is_attached()
  return M._attached == true
end

--- The id this instance names itself with at the relay.
---@return string
function M.client_id()
  return "nvim-" .. tostring(vim.fn.getpid())
end

--- `&client=<id>` for a URL to the relay while attached, else "".
---@return string
function M.client_param()
  if not M._attached then
    return ""
  end
  return "&client=" .. vim.uri_encode(M.client_id())
end

--- Whether this instance may push into the tab's room: always without a shared
--- relay, else only while it owns the room.
---@return boolean
function M.may_push()
  return not M._attached or M._owner
end

--- Where the shared relay advertises itself.
---@return string
function M.discovery_path()
  return vim.fn.stdpath("state") .. "/mdview/relay.json"
end

--- The extra relay arguments for a shared spawn (empty when not enabled).
---@return string[]
function M.spawn_args()
  if not M.enabled() then
    return {}
  end
  local idle = tonumber(cfg().idle_timeout_s) or 30
  return {
    "--shared",
    "--discovery-file",
    M.discovery_path(),
    "--idle-timeout",
    tostring(math.max(1, math.floor(idle))),
  }
end

---@internal
---@param port integer
---@param token string
---@return string
local function attach_url(port, token)
  return ("http://localhost:%d/attach?token=%s&client=%s"):format(
    port,
    vim.uri_encode(token),
    vim.uri_encode(M.client_id())
  )
end

--- Decode an /attach answer; nil unless it is a shared relay speaking our protocol.
---@param body string|nil
---@return table|nil status, string|nil why
function M.parse_status(body)
  if type(body) ~= "string" or body == "" then
    return nil, "no answer"
  end
  local ok, st = pcall(vim.json.decode, body)
  if not ok or type(st) ~= "table" then
    return nil, "not a shared relay (answered " .. body:sub(1, 60) .. ")"
  end
  if st.shared ~= true then
    return nil, "the relay at that port is not shared"
  end
  if st.protocol ~= M.PROTOCOL then
    return nil, ("the relay speaks shared protocol %s, this plugin %d"):format(tostring(st.protocol), M.PROTOCOL)
  end
  return st, nil
end

--- Read the discovery file.
---@return { port: integer, token: string }|nil
function M.read_discovery()
  local d = require("lib.nvim.fs.json").read(M.discovery_path())
  if type(d) ~= "table" or type(d.port) ~= "number" or type(d.token) ~= "string" or d.token == "" then
    return nil
  end
  return { port = d.port, token = d.token }
end

--- A short, blocking GET; the body, or nil when nothing answered. Replaced by
--- the specs.
---@param url string
---@return string|nil
function M._probe(url)
  if vim.fn.executable("curl") ~= 1 then
    return nil
  end
  local ok, out = pcall(vim.fn.system, { "curl", "-sS", "--max-time", "1", url })
  if not ok or vim.v.shell_error ~= 0 then
    return nil
  end
  return out
end

--- Find a running shared relay: the discovery file, confirmed by a short,
--- blocking `GET /attach` (a stale file -- relay gone, or another process on
--- the port -- is ignored; the relay spawned next replaces it).
---@return { port: integer, token: string, status: table }|nil info, string|nil why
function M.discover()
  local d = M.read_discovery()
  if not d then
    return nil, "no discovery file"
  end
  local out = M._probe(attach_url(d.port, d.token))
  if not out then
    return nil, "the relay in the discovery file does not answer"
  end
  local st, why = M.parse_status(out)
  if not st then
    return nil, why
  end
  return { port = d.port, token = d.token, status = st }, nil
end

--- Attach this instance to a discovered relay: its port and token become the
--- session's, and the tab it already has becomes this instance's preview room.
--- Not the owner yet: that takes a takeover (the launcher does one right away).
---@param info { port: integer, token: string, status: table }
---@return nil
function M.attach(info)
  local state = require("mdview.core.state")
  state.set_token(info.token)
  vim.g.mdview_server_port = info.port
  -- /attach just answered, so the relay is up: no /health round trip.
  require("mdview.adapter.ws_client")._ready = true
  M._attached = true
  M._owner = false
  M._claimed_at = 0
  M._tabs = type(info.status.tabs) == "table" and info.status.tabs or {}
  heartbeat_failures = 0
  heartbeat_ok_once = true
end

--- This instance just spawned the shared relay: it owns everything so far.
---@return nil
function M.mark_spawned()
  M._attached = true
  M._owner = true
  M._claimed_at = uv.now()
  M._tabs = {}
  heartbeat_failures = 0
  heartbeat_ok_once = false
end

--- Make this instance the owner of what it pushes next (a no-op without a
--- shared session). The relay records the claim from that push.
---@return nil
function M.claim()
  if not M._attached then
    return
  end
  M._owner = true
  M._claimed_at = uv.now()
end

--- The server handle an attached instance keeps in state.server (it has no
--- process of its own).
---@return table
function M.handle()
  return { shared = true }
end

--- A room with a connected tab this instance can follow, or nil.
---@return string|nil
function M.tab_room()
  local pk = require("mdview.core.state").get_preview_key()
  for _, room in ipairs(M._tabs) do
    if room == pk then
      return pk
    end
  end
  return M._tabs[1]
end

--- Take the tab over: push `bufnr` in full into the tab's room and name the
--- document, which makes this instance the room's owner at the relay. A no-op
--- without a shared session, without a tab, or for a buffer mdview does not
--- preview (the tab then keeps showing the other instance's document).
---@param bufnr integer|nil # defaults to the current buffer
---@return boolean claimed
function M.takeover(bufnr)
  if not M._attached then
    return false
  end
  local state = require("mdview.core.state")
  local room = M.tab_room()
  if not room then
    return false
  end
  if state.get_preview_key() ~= room then
    state.set_preview_key(room)
  end
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not require("mdview.helper.previewable").is(bufnr) then
    return false
  end
  local live_push = require("mdview.bindings.autocmds.live_push")
  local buffer_switch = require("mdview.bindings.autocmds.buffer_switch")
  -- Everything this instance remembers about the room describes it from before
  -- the other instance took it: forget it, so the document is named again and
  -- the content goes as a full snapshot, not as a diff against foreign text.
  live_push._last_doc[room] = nil
  buffer_switch._last = nil
  require("mdview.adapter.ws_client").reset_diff_state(room)
  M.claim()
  -- The spotlight mirror is per tab too: replace the other instance's.
  pcall(require("mdview.bindings.autocmds.spotlight_sync").resend)
  return buffer_switch.resync(bufnr)
end

--- Apply an /attach answer: follow the tab, and stop pushing once another
--- instance owns its room.
---@param st table
---@param sent_at integer|nil # uv.now() when the request was sent
---@return nil
function M.apply_status(st, sent_at)
  if not M._attached or type(st) ~= "table" then
    return
  end
  M._tabs = type(st.tabs) == "table" and st.tabs or {}
  local state = require("mdview.core.state")
  local room = M.tab_room()
  if room and state.get_preview_key() ~= room then
    state.set_preview_key(room)
  end
  -- `<=`: uv.now() is the loop's cached clock, so a heartbeat sent in the same
  -- loop iteration as the takeover carries the same stamp and may still have
  -- left before it.
  if sent_at and sent_at <= M._claimed_at then
    return
  end
  local owner = type(st.owners) == "table" and room and st.owners[room] or nil
  if type(owner) ~= "string" then
    return
  end
  local mine = owner == M.client_id()
  if M._owner and not mine and room then
    require("mdview.adapter.ws_client").reset_diff_state(room)
    require("mdview.bindings.autocmds.live_push")._last_doc[room] = nil
  end
  M._owner = mine
end

---@internal
---@return nil
local function relay_gone()
  M.stop_heartbeat()
  notify("[mdview] the shared relay is gone -- run :MDView start again", vim.log.levels.WARN)
  -- Detaching from a relay that is gone only costs a refused connection.
  pcall(require("mdview.bindings.usrcmds.stop").stop, false)
end

---@internal
---@return nil
local function heartbeat()
  if heartbeat_inflight or not M._attached then
    return
  end
  local token = require("mdview.core.state").get_token()
  local port = vim.g.mdview_server_port
  if type(token) ~= "string" or type(port) ~= "number" then
    return
  end
  heartbeat_inflight = true
  local sent_at = uv.now()
  local out = {}
  local ok, jid = pcall(vim.fn.jobstart, { "curl", "-sS", "--max-time", "2", attach_url(port, token) }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      out = data or {}
    end,
    on_exit = function(_, code)
      heartbeat_inflight = false
      vim.schedule(function()
        local st = code == 0 and M.parse_status(table.concat(out, "\n")) or nil
        if st then
          heartbeat_failures = 0
          heartbeat_ok_once = true
          M.apply_status(st, sent_at)
          return
        end
        -- Before the first answer the relay this instance spawned may still be
        -- coming up; only an answer that stops coming means it is gone.
        if heartbeat_ok_once then
          heartbeat_failures = heartbeat_failures + 1
          if heartbeat_failures >= 3 and M._attached then
            relay_gone()
          end
        end
      end)
    end,
  })
  if not ok or type(jid) ~= "number" or jid <= 0 then
    heartbeat_inflight = false
  end
end
M._heartbeat = heartbeat

--- Start the heartbeat (a no-op without a shared session).
---@return nil
function M.start_heartbeat()
  if not M._attached or heartbeat_timer then
    return
  end
  local every = tonumber(cfg().heartbeat_ms) or 2000
  heartbeat_timer = uv.new_timer()
  if not heartbeat_timer then
    return
  end
  heartbeat_timer:start(every, every, vim.schedule_wrap(heartbeat))
end

--- Stop the heartbeat.
---@return nil
function M.stop_heartbeat()
  if heartbeat_timer then
    heartbeat_timer:stop()
    pcall(heartbeat_timer.close, heartbeat_timer)
    heartbeat_timer = nil
  end
  heartbeat_inflight = false
end

--- Leave the shared relay (`:MDView stop`, quitting Neovim). Blocking and short,
--- like the close signal it replaces: on quit an async request would be lost.
--- The relay ends -- and closes the tab -- once no instance is left.
---@return nil
function M.detach()
  if not M._attached then
    return
  end
  M.stop_heartbeat()
  local token = require("mdview.core.state").get_token()
  local port = vim.g.mdview_server_port
  M._attached = false
  M._owner = false
  M._tabs = {}
  if type(token) ~= "string" or type(port) ~= "number" or vim.fn.executable("curl") ~= 1 then
    return
  end
  local url = ("http://localhost:%d/detach?token=%s&client=%s"):format(
    port,
    vim.uri_encode(token),
    vim.uri_encode(M.client_id())
  )
  pcall(vim.fn.system, { "curl", "-sS", "--max-time", "1", "-X", "POST", url })
end

--- Register the takeover triggers in the session's augroup (no-op without a
--- shared session): focus gained, and -- for terminals without focus reporting
--- -- the first activity in this instance while another one owns the tab.
---@param group integer|nil
---@return nil
function M.attach_autocmds(group)
  if not M._attached then
    return
  end
  local autocmd = require("lib.nvim.bindings.autocmd")
  local opts = { desc = "[mdview] Shared relay: the preview follows the focused instance" }
  if group then
    opts.group = group
  end
  -- Focus gained: always, since what this instance believes about owning the
  -- room can be up to one heartbeat old -- and following the focus is the point.
  -- Any other activity: only while another instance owns the room, so typing in
  -- the owner does not resend the whole document on every cursor move.
  autocmd.create({ "FocusGained", "CursorMoved", "CursorMovedI", "InsertEnter", "BufEnter" }, function(args)
    if M._attached and (args.event == "FocusGained" or not M._owner) then
      M.takeover(args.buf)
    end
  end, opts)
end

--- Forget everything (tests, a fresh session).
---@return nil
function M._reset()
  M.stop_heartbeat()
  M._attached = false
  M._owner = false
  M._claimed_at = 0
  M._tabs = {}
  heartbeat_failures = 0
  heartbeat_ok_once = false
end

return M

---@module 'mdview.bindings.autocmds.spotlight_sync'
-- Mirrors spotlight.nvim's highlights into the open preview: the tokens marked
-- in Neovim are marked, in the same colors, in the rendered document in the
-- browser -- for a log analysis or a case write-up that is shared or read over
-- someone's shoulder.
--
-- spotlight.nvim announces every change as a coalesced `User SpotlightChanged`
-- (at most one per editor tick) and says nothing else; this module re-reads
-- `require("spotlight").spotlights()` / `colors()` itself, builds one payload
-- (core/spotlight_mirror.lua) and POSTs it to the relay's `/spotlight` route,
-- which fans it out to every tab and keeps it for tabs that join later -- so a
-- freshly opened or reloaded preview shows the current spotlights at once.
--
-- What it does NOT do, on purpose:
--   * require spotlight.nvim. Without it nothing here ever runs a line that can
--     fail; the autocmds simply never fire.
--   * follow spotlight.nvim's persistence. A spotlight that is not persisted is
--     on screen in Neovim, so it is mirrored. `browser.spotlight_sync = false`
--     is the way to keep spotlights out of the preview.
--   * send what has not changed. The encoded payload is compared with the last
--     one the relay accepted; a burst of events, a no-op action and a colorscheme
--     switch that changed no color all cost nothing on the wire.
--
-- Gated per event on browser.spotlight_sync (default true), so
-- `:MDView spotlight off|on` takes effect on the running session.

local ws_client = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local mirror = require("mdview.core.spotlight_mirror")
local log = require("mdview.helper.log")
local autocmd = require("lib.nvim.bindings.autocmd")
local debounce = require("lib.nvim.debounce")
local defaults = require("mdview.config").defaults

local notify = require("lib.nvim.notify").create("").notify

local M = {}

--- Quiet period that turns a burst of changes into one read. spotlight.nvim has
--- already merged everything within one editor tick; this additionally absorbs
--- a `:colorscheme` (ColorScheme, then spotlight.nvim's own re-definition of
--- its groups, then its `colors` event) and a restore that touches the
--- registry in several ticks. Well inside the ~1 s the preview should lag by.
M.DEBOUNCE_MS = 120

--- JSON the relay last accepted for this session; nil = it holds nothing. Reset
--- with the session, because a new relay starts empty.
---@type string|nil
local last_json = nil

--- A POST is on its way: a request that arrives meanwhile only marks the state
--- dirty, so two requests can never overtake each other on the way to the relay.
local in_flight = false
local dirty = false

--- The "relay too old" warning is shown once per session, not once per change.
local warned_unsupported = false

---@type Lib.Debounce.Handle|nil
local debouncer = nil

--- Does `browser.spotlight_sync` currently allow sending anything?
---@return boolean
function M.enabled()
  return (defaults.browser or {}).spotlight_sync ~= false
end

--- What would be sent right now, as `{ json, count }`, or nil when there is
--- nothing to say: spotlight.nvim is absent, or there is nothing to clear.
---@internal
---@return string|nil json
---@return integer|nil count # spotlights in the payload
local function current()
  ---@type Mdview.SpotlightPayload|nil
  local payload
  if M.enabled() then
    payload = mirror.build()
  end
  if not payload or #payload.items == 0 then
    -- Nothing marked, switched off, or spotlight.nvim gone: tell the preview to
    -- drop its highlights -- but only if it was ever given any.
    if last_json == nil then
      return nil, nil
    end
    payload = mirror.empty()
  end
  local ok, json = pcall(vim.json.encode, payload)
  if not ok or type(json) ~= "string" then
    return nil, nil
  end
  return json, #payload.items
end

---@internal
---@return nil
local function send_now()
  if not state.get_server() then
    return
  end
  if in_flight then
    dirty = true
    return
  end
  local json, count = current()
  if not json or json == last_json then
    return
  end

  in_flight = true
  ws_client.send_spotlight(json, function(ok, err)
    in_flight = false
    if ok then
      last_json = json
      log.debug(("spotlight state sent (%d spotlights)"):format(count or 0), nil, "spotlight_sync", true)
    else
      -- Not retried here: the next SpotlightChanged / ColorScheme tries again,
      -- and a relay that does not know the route would otherwise be hammered.
      log.debug("spotlight state not accepted: " .. tostring(err), vim.log.levels.WARN, "spotlight_sync", true)
      if not warned_unsupported then
        warned_unsupported = true
        notify(
          "[mdview] the relay did not accept the spotlight state ("
            .. tostring(err)
            .. "). A relay older than the /spotlight route cannot mirror spotlights: update it "
            .. "(install.version, or dev.binary_path for a local build). "
            .. "Set browser.spotlight_sync = false to silence this.",
          vim.log.levels.WARN
        )
      end
    end
    if dirty then
      dirty = false
      send_now()
    end
  end)
end

--- Read spotlight.nvim and send the result if it changed -- right now, without
--- the debounce. Waits for the relay to answer /health first (the session start
--- calls this before the relay is up). Exported for `:MDView spotlight` and tests.
---@return nil
function M.sync_now()
  if not state.get_server() then
    return
  end
  ws_client.wait_ready(function(ok)
    if ok then
      send_now()
    end
  end)
end

--- Ask for a sync, debounced: a burst of changes reads the state once.
---@return nil
function M.request()
  if debouncer then
    debouncer.call()
  end
end

--- Forget what was sent and drop a pending debounce. Called when a session ends
--- (the next relay starts empty, so the next send must not be deduplicated
--- against a tab that is no longer there) and by tests.
---@return nil
function M.reset()
  if debouncer then
    debouncer.cancel()
  end
  last_json = nil
  in_flight = false
  dirty = false
  warned_unsupported = false
end

--- Setup the autocmds: `User SpotlightChanged` and the colorscheme triggers.
---
--- Always attached, and gated per event on browser.spotlight_sync, so
--- `:MDView spotlight on` works on the running session. spotlight.nvim does not
--- have to be loaded yet -- a `User` autocmd is matched by name, and a plugin
--- that loads later fires into it.
---@param group integer|nil
---@return nil
function M.attach(group)
  M.reset()
  debouncer = debounce.new(M.sync_now, M.DEBOUNCE_MS)

  local pattern = "SpotlightChanged"
  local ok_events, events = pcall(require, "spotlight.core.events")
  if ok_events and type(events) == "table" and type(events.PATTERN) == "string" then
    pattern = events.PATTERN
  end

  autocmd.create("User", function(args)
    if not M.enabled() then
      return
    end
    local data = args.data
    -- Only "this occurrence only" spotlights changed: nothing in the preview
    -- depends on them. (A missing payload means an older spotlight.nvim: sync.)
    if type(data) == "table" and data.whole_file_changed == false then
      return
    end
    M.request()
  end, {
    desc = "[mdview] Mirror spotlight.nvim's spotlights into the browser preview",
    pattern = pattern,
    group = group,
  })

  -- spotlight.nvim reports a palette change itself (reason "colors") -- unless
  -- its `palette.reapply_on_colorscheme` is off, in which case it is silent and
  -- the browser would keep the old colors. Listening here too costs nothing:
  -- the payload is compared before it is sent.
  autocmd.create({ "ColorScheme" }, function()
    if M.enabled() then
      M.request()
    end
  end, {
    desc = "[mdview] Re-send the spotlight colors after a colorscheme change",
    group = group,
  })

  autocmd.create("OptionSet", function()
    if M.enabled() then
      M.request()
    end
  end, {
    desc = "[mdview] Re-send the spotlight colors after 'background' changed",
    pattern = "background",
    group = group,
  })

  -- The state the preview should start with. The relay is not up yet when a
  -- session attaches; sync_now waits for it.
  M.request()
end

return M

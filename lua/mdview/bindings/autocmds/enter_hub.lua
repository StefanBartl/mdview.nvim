---@module 'mdview.bindings.autocmds.enter_hub'
--- The session's BufEnter handlers behind ONE autocmd.
---
--- Three features act on entering a previewable buffer (the content snapshot,
--- `browser.behavior` on a buffer switch, session breadcrumbs), and each used
--- to register its own BufEnter autocmd, each re-deriving "is this buffer
--- something mdview previews, and what is its normalized path?". Here the gate
--- is the dispatch key and the path is the shared context, so both are worked
--- out once per event and handed to whoever needs them.
---
--- This is a structure change, not a speed one. Neovim's own `pattern` matching
--- is passed straight through (`ft_pattern`), so a buffer outside it never
--- enters Lua, and a hit costs the one Lua entry it always did; see
--- `lib.nvim.bindings.autocmd.dispatcher`'s README for the measurements.
---
--- Only the BufEnter handlers live here. The cursor/text/write autocmds each
--- have a single handler on their own event, so a dispatcher would add a layer
--- and nothing else.
---
--- No handler depends on another's order: `buffer_switch` reads the buffer
--- itself, never the snapshot `bufenter` stores. Ties run in registration
--- order, which is the order `bindings/autocmds/init.lua` attaches them in --
--- the order they ran in as separate autocmds.
---
--- Lifecycle, driven by `bindings/autocmds/init.lua`: each feature calls
--- `register()` from its `attach()`, and `reset()` from `teardown()` takes
--- them all back out. The dispatcher itself is kept across sessions and only
--- detached, so a restart re-attaches the same object instead of stacking a new
--- one on lib's list of live dispatchers.

local api = vim.api
local dispatcher = require("lib.nvim.bindings.autocmd.dispatcher")
local previewable = require("mdview.helper.previewable")
local normalize = require("mdview.helper.normalize")

local M = {}

--- The only key: the event is dispatched if the buffer is previewable at all.
local KEY = "previewable"

--- Same group the rest of the session lives in (`bindings/autocmds/init.lua`).
local GROUP = "MdviewAutocmds"

---@type Lib.Autocmd.Dispatcher.Handle|nil
local handle = nil
--- `ft_pattern` the current dispatcher was built with. It is fixed at `new()`,
--- and `any_file` widens it at setup time, so a change means a rebuild.
---@type string|nil
local built_for = nil
---@type table<string, true>
local owners = {}

---@class Mdview.EnterHub.Context
---@field path string|nil  # normalized path of the entered buffer; nil if it could not be normalized

---@internal
---@return Lib.Autocmd.Dispatcher.Handle
local function ensure()
  local pattern = require("mdview.config").defaults.ft_pattern
  local signature = vim.inspect(pattern)
  if handle and built_for ~= signature then
    handle.detach()
    handle = nil
  end
  if not handle then
    handle = dispatcher.new({
      event = "BufEnter",
      name = "mdview_bufenter",
      group = GROUP,
      pattern = pattern,
      desc = "[mdview] Dispatch entering a previewable buffer to its handlers",
      key = function(ev)
        return previewable.is(ev.buf) and KEY or nil
      end,
      ---@return Mdview.EnterHub.Context
      context = function(ev)
        return { path = normalize.path(api.nvim_buf_get_name(ev.buf)) }
      end,
    })
    built_for = signature
  end
  return handle
end

--- Register one handler for entering a previewable buffer.
---
--- `owner` names the feature; `reset()` takes it back out. `spec.load` gets the
--- dispatcher's context, whose `context` field is a `Mdview.EnterHub.Context`.
---@param owner string
---@param spec { load: fun(ctx: Lib.Autocmd.Dispatcher.Ctx), desc: string, priority?: integer }
---@return Lib.Autocmd.Dispatcher.Handle
function M.register(owner, spec)
  local h = ensure()
  h.attach() -- idempotent; a handler registered later is picked up without re-attaching
  owners[owner] = true
  -- A tail call, deliberately: lib records the `register()` call site off the
  -- stack so the generated bindings table names the feature's file, and a
  -- wrapper frame here would attribute every handler to this line instead.
  return h.register(KEY, {
    load = spec.load,
    desc = spec.desc,
    priority = spec.priority,
    owner = owner,
  })
end

--- Take every handler back out and detach the dispatcher. Safe to call when
--- nothing was ever registered, and safe to call twice.
---@return nil
function M.reset()
  if not handle then
    return
  end
  for owner in pairs(owners) do
    handle.unregister(owner)
  end
  owners = {}
  handle.detach()
end

return M

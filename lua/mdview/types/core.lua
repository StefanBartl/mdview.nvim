---@module 'mdview.types.core'

---@class mdview.core.state.web
---@field attached boolean whether web subsystem is attached/active
---@field browser any opaque browser handle (or nil)
---@field server any opaque server/runner handle (or nil)

---@class mdview.core.state.runner
---@field proc SpawnedProcess|nil The spawned relay process, as `state.set_proc` files it away.
---@field server_job integer|nil
---@field token string|nil shared session token for the running mdview-server process
---@field is_running boolean|nil whether the relay process is currently running
---@field preview_key string|nil relay room key the visible browser tab is bound to (see browser.behavior)

---@alias URL string # must be a valid HTTP(S) address, e.g. "http://localhost:43219"

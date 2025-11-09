---@module 'mdview.types.core'

---@class mdview.core.state.web
---@field attached boolean whether web subsystem is attached/active
---@field browser any opaque browser handle (or nil)
---@field server any opaque server/runner handle (or nil)

---@class mdview.core.state.runner
---@field proc integer|nil
---@field server_job integer|nil

---@alias URL string # must be a valid HTTP(S) address, e.g. "http://localhost:43219"

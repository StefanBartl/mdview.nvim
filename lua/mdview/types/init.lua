---@module 'mdview.types'

-- == init ==
---@class mdview
---@field config table
---@field state table

-- == config ==
---@class mdview.config
---@field server_port integer preferred port the server listens on
---@field server_cwd string|nil optional working directory override for the server
---@field dev_local boolean developer-only flags

-- == core/session ==
-- `hash` (sha256 of the lines joined by "\n") is computed on first read, then memoized.
---@class mdview.session.entry
---@field lines string[]
---@field hash string

---@class mdview.session
---@field buffers table<string, mdview.session.entry>

-- == core/events ==
---@class mdview.events
---@field augroup integer

-- == adapter/ws_client ==
---@class mdview.ws_client
---@field last_request table<string, number> timestamp map per path

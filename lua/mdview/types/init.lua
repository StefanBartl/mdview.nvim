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
---@class mdview.session
---@field buffers table<string, { hash: string, lines: string[] }>

-- == core/events ==
---@class mdview.events
---@field augroup integer

-- == adapter/runner ==
---@class mdview.runner
---@field proc table|nil
---@field handle userdata|nil
---@field pid integer|nil


-- == adapter/ws_client ==
---@class mdview.ws_client
---@field last_request table<string, number> timestamp map per path


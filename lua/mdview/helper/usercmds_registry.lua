---@module 'mdview.helper.usercmds_registry'
--- Helper to track and cleanup usercommands.
--- Registration itself goes through lib.nvim's usercmd wrapper, which adds
--- pcall-safety around the callback (an error in a command handler gets
--- reported via notify instead of aborting silently); this module adds the
--- name-tracking + bulk teardown lib.nvim's wrapper doesn't provide.

local api = vim.api
local libusercmd = require("lib.nvim.usercmd")

local M = {}

---@type table<string, boolean>
M._registered = {}

--- Register a usercommand and track it for potential cleanup.
--- Important: 'MDViewStart' and 'MDViewShowWeblog' are not registered here, because they should be available at anytime
---@param name string
---@param cmd_fun fun()
---@param opts table
function M.register(name, cmd_fun, opts)
    opts = opts or {}
    libusercmd.create(name, cmd_fun, opts)
    M._registered[name] = true
end

--- Remove all registered usercommands.
function M.detach_all()
    for name, _ in pairs(M._registered) do
        pcall(api.nvim_del_user_command, name)
    end
    M._registered = {}
end

return M

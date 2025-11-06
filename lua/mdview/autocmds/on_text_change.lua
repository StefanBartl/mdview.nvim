---@module 'mdview.autocmds.on_text_changed'
-- Live markdown push on insert/change

local api = vim.api
local push_buffer = require("mdview.core.events").push_buffer
local log = require("mdview.helper.log")

local M = {}

local function on_text_changed(bufnr)
    log.debug("TextChanged fired for buf " .. bufnr, nil, "textchange", true)
    push_buffer(bufnr, false)  -- only push diffs
end

function M.setup()
    api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        pattern = "*.md",
        callback = function(args) on_text_changed(args.buf) end,
    })
end

return M

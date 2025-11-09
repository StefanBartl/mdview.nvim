---@module 'mdview.helper.autocmds_registry'
--- Central helper to manage autocmd registration and cleanup.

local api = vim.api

local M = {}

-- Store autocmd IDs per augroup
---@type table<integer, integer[]>
M._autocmd_ids = {}

--- Register an autocmd ID for a given augroup
--- @param group integer|nil
--- @param id integer
function M.register(group, id)
    if not group then return end
    M._autocmd_ids[group] = M._autocmd_ids[group] or {}
    table.insert(M._autocmd_ids[group], id)
end

--- Remove all autocmds for the given augroup
--- @param group integer|nil
function M.detach(group)
    if not group then return end
    local ids = M._autocmd_ids[group]
    if not ids then return end

    for _, id in ipairs(ids) do
        pcall(api.nvim_del_autocmd, id)
    end
    M._autocmd_ids[group] = nil
end

--- Detach all registered autocmds across all augroups
function M.detach_all()
    for group, _ in pairs(M._autocmd_ids) do
        M.detach(group)
    end
end

return M

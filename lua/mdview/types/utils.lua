---@module 'mdview.types.utils'

-- == utils.diff ==
---@class DiffEdit
---@field op "replace" | "insert" | "delete" Operation type
---@field start number zero-based start index
---@field count number number of lines in old content to replace/delete
---@field lines string[]|nil new lines for replace/insert operations

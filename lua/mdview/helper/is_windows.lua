---@module 'mdview.helper.is_windows'
-- Detect native Windows (not WSL). Delegates to lib.nvim, which mdview.nvim
-- depends on for this and other small cross-platform helpers (see README's
-- Installation section for the required lazy.nvim `dependencies` entry).

---@return boolean
return require("lib.nvim.cross.platform.is_windows")

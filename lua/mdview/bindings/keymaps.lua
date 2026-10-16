---@module 'mdview.bindings.keymaps'
--- Opt-in keymaps. mdview.nvim maps nothing by default (the `:MDView` command
--- is its whole surface); a lhs set under `keymaps` in setup() maps the matching
--- action in normal mode:
---
---   keymaps = { write = "<leader>mw" }   -> :MDView write toggle
---
--- Registered once at setup(), like the user commands, and never torn down.

local M = {}

--- Map every configured keymap. A missing, `false` or empty lhs maps nothing.
---@param keymaps mdview.config.KeymapsDefaults|nil
---@return string[] mapped  # the lhs strings that were mapped (for tests)
function M.attach(keymaps)
  local mapped = {}
  if type(keymaps) ~= "table" then
    return mapped
  end

  local lhs = keymaps.write
  if type(lhs) == "string" and lhs ~= "" then
    require("lib.nvim.bindings.keymap.set")("n", lhs, function()
      require("mdview.bindings.usrcmds.write").run("toggle")
    end, nil, "mdview: toggle write mode (caret + block editing)")
    mapped[#mapped + 1] = lhs
  end

  return mapped
end

return M

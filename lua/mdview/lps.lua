---@module 'mdview.lsp'

require("lspconfig").lua_ls.setup({
  settings = {
    Lua = {
      diagnostics = {
        globals = { "describe", "it", "setup", "teardown", "before_each", "after_each" },
      },
    },
  },
})

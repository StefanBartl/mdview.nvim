-- .luacheckrc
-- `vim` is a real global injected by Neovim at runtime; without declaring it
-- here, luacheck flags nearly every file in this plugin as using an
-- undefined global, drowning out warnings that actually matter.
globals = {
  "vim",
}

-- Neovim Lua conventions favor readability over a hard line-length cap;
-- don't fail CI on line length alone.
max_line_length = false

-- testing.nvim's busted dialect provides describe/it/assert globals.
files["TESTS/**/*_spec.lua"] = { std = "+busted" }

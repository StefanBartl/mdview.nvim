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

-- busted specs get their describe/it/assert globals from the test runner.
files["tests/lua/**/*_spec.lua"] = { std = "+busted" }

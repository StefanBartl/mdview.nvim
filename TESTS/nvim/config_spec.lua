---@module 'tests.nvim.config_spec'
-- Verifies the two config defaults that decide which buffers mdview follows:
-- `ft_pattern` (the autocmd globs) and `any_file` (which widens them), plus
-- the deprecated `experimental.any_file` alias the latter shipped under until
-- 2026-08-30. Both were regressions once — see DEFAULTS.lua's comments.

---@diagnostic disable: undefined-global

local config = require("mdview.config")

--- merge() mutates the shared module defaults in place, so every case has to
--- put the two keys back the way it found them — otherwise a later spec (or a
--- later case here) inherits a widened ft_pattern.
---@param fn fun()
---@return nil
local function with_clean_defaults(fn)
  local orig_any = config.defaults.any_file
  local orig_ft = vim.deepcopy(config.defaults.ft_pattern)
  local orig_exp = config.defaults.experimental and config.defaults.experimental.any_file
  local ok, err = pcall(fn)
  config.defaults.any_file = orig_any
  config.defaults.ft_pattern = orig_ft
  if config.defaults.experimental then
    config.defaults.experimental.any_file = orig_exp
  end
  if not ok then
    error(err)
  end
end

describe("config.defaults.ft_pattern", function()
  --- Neovim matches an autocmd pattern that contains no `/` against the file
  --- name, so a bare extension like ".markdown" only ever matches a file
  --- *named* `.markdown`. Every default has to be a real glob, or edits in the
  --- files it is meant to cover reach no autocmd at all.
  ---@param pattern string
  ---@param name string
  ---@return boolean
  local function matches(pattern, name)
    return vim.fn.match(name, vim.fn.glob2regpat(pattern)) >= 0
  end

  it("covers .md, .markdown and .mdx files", function()
    for _, name in ipairs({ "notes.md", "notes.markdown", "notes.mdx" }) do
      local hit = false
      for _, pattern in ipairs(config.defaults.ft_pattern) do
        hit = hit or matches(pattern, name)
      end
      assert.is_true(hit)
    end
  end)

  it("has no bare-extension pattern left", function()
    for _, pattern in ipairs(config.defaults.ft_pattern) do
      assert.is_false(pattern:sub(1, 1) == ".")
    end
  end)
end)

describe("config.merge any_file", function()
  it("leaves ft_pattern Markdown-only by default", function()
    with_clean_defaults(function()
      local merged = config.merge({})
      assert.is_false(merged.any_file == true)
      assert.is_false(vim.deep_equal(merged.ft_pattern, { "*" }))
    end)
  end)

  it('widens ft_pattern to { "*" } when any_file is on', function()
    with_clean_defaults(function()
      local merged = config.merge({ any_file = true })
      assert.is_true(merged.any_file)
      assert.is_true(vim.deep_equal(merged.ft_pattern, { "*" }))
    end)
  end)

  it("still honors the deprecated experimental.any_file alias", function()
    with_clean_defaults(function()
      local merged = config.merge({ experimental = { any_file = true } })
      assert.is_true(merged.any_file)
      assert.is_true(vim.deep_equal(merged.ft_pattern, { "*" }))
    end)
  end)

  it("lets an explicit any_file = false win over the alias", function()
    with_clean_defaults(function()
      local merged = config.merge({ any_file = false, experimental = { any_file = true } })
      assert.is_false(merged.any_file)
      assert.is_false(vim.deep_equal(merged.ft_pattern, { "*" }))
    end)
  end)

  it("beats a hand-set ft_pattern", function()
    with_clean_defaults(function()
      local merged = config.merge({ any_file = true, ft_pattern = { "*.md" } })
      assert.is_true(vim.deep_equal(merged.ft_pattern, { "*" }))
    end)
  end)
end)

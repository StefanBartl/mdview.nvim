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

describe("config.merge starts from DEFAULTS", function()
  local DEFAULTS = require("mdview.config.DEFAULTS")

  after_each(function()
    config.merge({})
  end)

  it("brings back an option a later call leaves out", function()
    config.merge({ server_port = 1111, browser = { theme = "dark-x", browser = "firefox" } })
    assert.equals(1111, config.defaults.server_port)
    config.merge({ dev_server_port = 2222 })
    assert.equals(DEFAULTS.server_port, config.defaults.server_port)
    assert.equals(DEFAULTS.browser.theme, config.defaults.browser.theme)
    assert.equals(DEFAULTS.browser.browser, config.defaults.browser.browser)
    assert.equals(2222, config.defaults.dev_server_port)
  end)

  it("treats merge(nil) and merge({}) as the defaults", function()
    config.merge({ server_port = 1111 })
    config.merge(nil)
    assert.equals(DEFAULTS.server_port, config.defaults.server_port)
    config.merge({ server_port = 1111 })
    config.merge({})
    assert.equals(DEFAULTS.server_port, config.defaults.server_port)
  end)

  it("keeps the sub-tables other modules point at", function()
    local browser, start = config.defaults.browser, config.defaults.start
    config.merge({ browser = { browser = "firefox" }, start = { wait_timeout_ms = 5 } })
    config.merge({})
    assert.is_true(browser == config.defaults.browser, "browser sub-table identity")
    assert.is_true(start == config.defaults.start, "start sub-table identity")
    assert.equals("", browser.browser)
  end)

  it("never writes into DEFAULTS", function()
    local before = vim.deepcopy(DEFAULTS)
    config.merge({ server_port = 1111, browser = { theme = "x" }, ft_pattern = { "*.txt" } })
    config.defaults.browser.theme = "changed-live"
    config.merge({})
    assert.is_true(vim.deep_equal(DEFAULTS, before), "DEFAULTS is untouched")
  end)

  it("replaces a list of the user's instead of merging it index by index", function()
    config.merge({ ft_pattern = { "*.txt" } })
    assert.same({ "*.txt" }, config.defaults.ft_pattern)
  end)

  it("does not keep the user's tables", function()
    local opts = { browser = { browser_args = { "--a" } } }
    config.merge(opts)
    config.defaults.browser.browser_args[1] = "--changed"
    assert.equals("--a", opts.browser.browser_args[1])
    config.merge({ browser = { browser_args = { "--b" } } })
    assert.equals("--a", opts.browser.browser_args[1])
  end)
end)

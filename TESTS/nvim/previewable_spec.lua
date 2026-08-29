---@module 'tests.nvim.previewable_spec'
-- Verifies mdview.helper.previewable: the shared "is this buffer something
-- mdview should preview" gate that every autocmd (bufenter, live_push,
-- breadcrumbs, buffer_switch, scroll_sync) now calls. Covers both the
-- default (experimental.any_file = false, today's Markdown-only behavior)
-- and the any_file = true case (see DEFAULTS.lua / config/init.lua).

---@diagnostic disable: undefined-global

local previewable = require("mdview.helper.previewable")
local config = require("mdview.config")

---@param filetype string
---@param buftype string|nil
---@param name string|nil
---@return integer bufnr
local function make_buf(filetype, buftype, name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name or ("mdview_spec_previewable_" .. buf))
  vim.bo[buf].filetype = filetype
  vim.bo[buf].buftype = buftype or ""
  return buf
end

describe("previewable.is (experimental.any_file = false, default)", function()
  it("accepts a markdown-filetype buffer", function()
    local buf = make_buf("markdown")
    assert.is_true(previewable.is(buf))
  end)

  it("accepts the 'md' filetype alias", function()
    local buf = make_buf("md")
    assert.is_true(previewable.is(buf))
  end)

  it("rejects a non-markdown filetype", function()
    local buf = make_buf("lua")
    assert.is_false(previewable.is(buf))
  end)

  it("rejects an unnamed buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.bo[buf].filetype = "markdown"
    assert.is_false(previewable.is(buf))
  end)
end)

describe("previewable.is (experimental.any_file = true)", function()
  local orig

  local function set_any_file(on)
    config.defaults.experimental.any_file = on
  end

  it("accepts a normal-buftype non-markdown buffer", function()
    orig = config.defaults.experimental.any_file
    set_any_file(true)
    local buf = make_buf("lua")
    assert.is_true(previewable.is(buf))
    set_any_file(orig)
  end)

  it("still rejects non-normal buftypes (nofile/prompt, standing in for terminal/help/quickfix)", function()
    -- Neovim rejects setting buftype=terminal/help/quickfix by direct
    -- assignment outside its own internal setup (E474), so this exercises
    -- the same `buftype ~= ""` gate in previewable.is via buftypes that
    -- *can* be set directly — the gate itself doesn't special-case any
    -- particular non-empty buftype.
    orig = config.defaults.experimental.any_file
    set_any_file(true)
    assert.is_false(previewable.is(make_buf("markdown", "nofile", "spec-scratch")))
    assert.is_false(previewable.is(make_buf("markdown", "prompt", "spec-prompt")))
    set_any_file(orig)
  end)

  it("still rejects mdview's own log scratch buffer", function()
    orig = config.defaults.experimental.any_file
    set_any_file(true)
    local buf = make_buf("log", "", config.defaults.log_buffer_name)
    assert.is_false(previewable.is(buf))
    set_any_file(orig)
  end)

  it("still rejects a binary buffer", function()
    orig = config.defaults.experimental.any_file
    set_any_file(true)
    local buf = make_buf("", "", "spec-binary.bin")
    vim.bo[buf].binary = true
    assert.is_false(previewable.is(buf))
    set_any_file(orig)
  end)
end)

---@module 'tests.nvim.preview_tab_spec'
-- Verifies mdview.adapter.preview_tab: the in-Neovim-tab Markdown preview
-- (:MDView preview-tab), which is fully independent of the browser/relay
-- pipeline. No coverage existed for this feature at all. Particular focus on
-- the buffer/window teardown paths this campaign keeps finding bugs in:
-- what happens to the module's bookkeeping when the preview buffer is wiped
-- out from under it by something OTHER than M.close() itself (:bwipeout, a
-- file explorer or a real file taking over its tab).

---@diagnostic disable: undefined-global

local preview_tab = require("mdview.adapter.preview_tab")

local orig_notify = vim.notify
vim.notify = function() end

--- A real, named, listed Markdown buffer with the given lines.
---@param name string
---@param lines string[]
---@return integer
local function make_md_buffer(name, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe("preview_tab.open/close/toggle", function()
  local source = make_md_buffer("mdview_spec_preview_tab.md", { "# Title", "body line" })

  it("refuses a non-markdown buffer", function()
    local plain = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(plain, "mdview_spec_preview_tab_plain.lua")
    vim.api.nvim_set_option_value("filetype", "lua", { buf = plain })
    local tabs_before = vim.fn.tabpagenr("$")
    assert.is_false(preview_tab.open(plain))
    assert.are.equal(tabs_before, vim.fn.tabpagenr("$"))
  end)

  it("opens a new tab with a read-only mirror of the source buffer", function()
    local tabs_before = vim.fn.tabpagenr("$")
    assert.is_true(preview_tab.open(source))
    assert.are.equal(tabs_before + 1, vim.fn.tabpagenr("$"))

    local preview_buf = vim.api.nvim_get_current_buf()
    assert.is_true(preview_buf ~= source)
    assert.are.same({ "# Title", "body line" }, vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false))
    assert.are.equal("nofile", vim.bo[preview_buf].buftype)
    assert.are.equal("wipe", vim.bo[preview_buf].bufhidden)
    assert.are.equal("markdown", vim.bo[preview_buf].filetype)
    assert.is_false(vim.bo[preview_buf].modifiable)

    -- nvim_buf_set_name resolves a bare synthetic name against cwd, so only
    -- the trailing "[mdview preview] <basename> (<bufnr>)" part is checked.
    local name = vim.api.nvim_buf_get_name(preview_buf)
    assert(
      name:match("%[mdview preview%] mdview_spec_preview_tab%.md %(%d+%)$"),
      "unexpected preview buffer name: " .. name
    )
  end)

  it("is_open reports true from either side of the source/preview pair", function()
    assert.is_true(preview_tab.is_open(source))
    local preview_buf = vim.api.nvim_get_current_buf()
    assert.is_true(preview_tab.is_open(preview_buf))
  end)

  it("sync() mirrors source edits into the preview, preserving the window's cursor", function()
    local preview_buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(win, { 2, 0 })

    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "# Title", "body line", "a third line" })
    preview_tab.sync(source)

    assert.are.same({ "# Title", "body line", "a third line" }, vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false))
    assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
    assert.is_false(vim.bo[preview_buf].modifiable) -- restored after the write
  end)

  it("re-opening an already-open preview focuses the existing window instead of creating a new tab", function()
    local preview_win = vim.api.nvim_get_current_win()
    local preview_tabpage = vim.api.nvim_get_current_tabpage()

    -- Split away first (same tab, no new tabpage) so "already open" really
    -- has to search for the window rather than finding "whatever is current".
    vim.cmd("new")
    local split_win = vim.api.nvim_get_current_win()
    assert.is_true(split_win ~= preview_win)

    local tabs_before = vim.fn.tabpagenr("$")
    assert.is_true(preview_tab.open(source))
    assert.are.equal(tabs_before, vim.fn.tabpagenr("$")) -- no net new tab
    assert.are.equal(preview_win, vim.api.nvim_get_current_win())
    assert.are.equal(preview_tabpage, vim.api.nvim_get_current_tabpage())

    vim.api.nvim_win_close(split_win, true)
  end)

  it("toggle() closes an open preview: window and buffer both go away", function()
    assert.is_true(preview_tab.is_open(source))
    -- Focus it (open() on an already-open preview just focuses).
    preview_tab.open(source)
    local preview_buf = vim.api.nvim_get_current_buf()

    local tabs_before = vim.fn.tabpagenr("$")
    preview_tab.toggle(source)

    assert.is_false(preview_tab.is_open(source))
    assert.are.equal(tabs_before - 1, vim.fn.tabpagenr("$"))
    assert.is_false(vim.api.nvim_buf_is_valid(preview_buf))
  end)

  it("toggle() re-opens once closed", function()
    assert.is_false(preview_tab.is_open(source))
    preview_tab.toggle(source)
    assert.is_true(preview_tab.is_open(source))
  end)

  it("close() on either side of the pair tears the tab/buffer down", function()
    local preview_buf = vim.api.nvim_get_current_buf()
    preview_tab.close(preview_buf) -- closing via the PREVIEW side, not the source
    assert.is_false(preview_tab.is_open(source))
    assert.is_false(vim.api.nvim_buf_is_valid(preview_buf))
  end)
end)

describe("preview_tab bookkeeping on external buffer teardown", function()
  local source = make_md_buffer("mdview_spec_preview_tab_wipe.md", { "content" })

  it("forgets the mapping when the preview buffer is wiped directly (:bwipeout)", function()
    preview_tab.open(source)
    local preview_buf = vim.api.nvim_get_current_buf()
    assert.is_true(preview_tab.is_open(source))

    -- Not through M.close(): the BufWipeout autocmd registered in M.open()
    -- must be the thing that forgets the mapping here.
    vim.cmd("bwipeout! " .. preview_buf)

    assert.is_false(preview_tab.is_open(source))
    assert.is_false(preview_tab.is_open(preview_buf))
  end)

  it("opening again afterward starts a clean new preview rather than reusing a stale mapping", function()
    local ok = pcall(preview_tab.open, source)
    assert.is_true(ok)
    assert.is_true(preview_tab.is_open(source))
    preview_tab.close(source)
  end)
end)

describe("preview_tab.handle_displacement", function()
  local source = make_md_buffer("mdview_spec_preview_tab_displace.md", { "content" })

  it("closes the preview once something else takes over its tab", function()
    preview_tab.open(source)
    assert.is_true(preview_tab.is_open(source))

    -- Simulate a file/explorer taking over the preview's tab: switch the
    -- CURRENT window (still the preview's tab) to a different real buffer.
    local other = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(other, "mdview_spec_preview_tab_displace_other.md")
    vim.api.nvim_set_current_buf(other)

    preview_tab.handle_displacement()
    vim.wait(100, function()
      return not preview_tab.is_open(source)
    end)

    assert.is_false(preview_tab.is_open(source))
  end)

  it("does nothing when focus is already on the preview buffer itself", function()
    preview_tab.open(source)
    local preview_buf = vim.api.nvim_get_current_buf()
    assert.is_true(preview_tab.is_open(preview_buf))

    local ok, err = pcall(preview_tab.handle_displacement)
    vim.wait(50)

    assert.is_true(ok, tostring(err))
    assert.is_true(preview_tab.is_open(preview_buf))
    preview_tab.close(source)
  end)
end)

vim.notify = orig_notify

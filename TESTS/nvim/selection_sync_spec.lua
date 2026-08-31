---@module 'tests.nvim.selection_sync_spec'
-- Covers the Neovim half of the visual-selection mirror: turning whatever
-- v / V / CTRL-V currently has selected into the (mode, line, byte column)
-- payload the browser client draws, and routing that payload to the room the
-- open tab actually watches.
--
-- The client half — mapping those coordinates onto DOM positions — is covered
-- in TESTS/client/selectionMarker.test.ts.

---@diagnostic disable: undefined-global, need-check-nil, duplicate-set-field

local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local selection_sync = require("mdview.bindings.autocmds.selection_sync")
local bcfg = require("mdview.config.browser")
local normalize = require("mdview.helper.normalize")

-- Capture what control.send hands the transport, and where it routes it.
local last_key, last_json
local orig_send_control = ws.send_control
ws.send_control = function(key, json)
  last_key, last_json = key, json
end

local function make_md_buffer(name, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function leave_visual()
  vim.cmd("normal! \27") -- <Esc>
end

describe("selection_sync.current", function()
  local buf = make_md_buffer("mdview_spec_selection.md", { "hello world", "second line", "third" })
  vim.api.nvim_set_current_buf(buf)
  vim.o.selection = "inclusive"

  it("is nil outside a visual mode", function()
    leave_visual()
    assert.is_nil(selection_sync.current())
  end)

  it("reports a charwise selection with 1-based byte columns", function()
    leave_visual()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v4l") -- "hello" -> columns 1..5 on line 1
    local sel = selection_sync.current()
    leave_visual()
    assert.are.same({ mode = "char", sl = 1, sc = 1, el = 1, ec = 5 }, sel)
  end)

  it("orders the ends even when the cursor sits above the anchor", function()
    leave_visual()
    vim.api.nvim_win_set_cursor(0, { 2, 2 })
    vim.cmd("normal! vk") -- anchor on line 2, cursor moves up to line 1
    local sel = selection_sync.current()
    leave_visual()
    assert.are.equal("char", sel.mode)
    assert.are.equal(1, sel.sl)
    assert.are.equal(2, sel.el)
  end)

  it("reports a linewise selection", function()
    leave_visual()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! Vj")
    local sel = selection_sync.current()
    leave_visual()
    assert.are.equal("line", sel.mode)
    assert.are.equal(1, sel.sl)
    assert.are.equal(2, sel.el)
  end)

  it("reports a blockwise selection with its columns ordered left to right", function()
    leave_visual()
    vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- column 5
    vim.cmd("normal! \22j2h") -- CTRL-V down one line, then left: cursor ends left of the anchor
    local sel = selection_sync.current()
    leave_visual()
    assert.are.equal("block", sel.mode)
    assert.are.equal(3, sel.sc)
    assert.are.equal(5, sel.ec)
  end)

  it("drops the character under the cursor when 'selection' is exclusive", function()
    leave_visual()
    vim.o.selection = "exclusive"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v4l")
    local sel = selection_sync.current()
    leave_visual()
    vim.o.selection = "inclusive"
    assert.are.equal(4, sel.ec)
  end)
end)

describe("selection_sync.send_current_selection", function()
  local buf = make_md_buffer("mdview_spec_selection_send.md", { "hello world", "second line" })
  local buf_key = normalize.path(vim.api.nvim_buf_get_name(buf))
  vim.api.nvim_set_current_buf(buf)
  vim.o.selection = "inclusive"
  state.set_server({ stub = true }) -- control.send is a no-op without a session
  bcfg.defaults.behavior = "new_tab" -- route to the buffer's own path
  bcfg.defaults.selection_sync = true -- off by default; switched on for these

  it("routes the selection to the room the tab watches", function()
    leave_visual()
    selection_sync.reset()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v4l")
    last_key, last_json = nil, nil
    selection_sync.send_current_selection(buf)
    leave_visual()
    assert.are.equal(buf_key, last_key)
    local msg = vim.json.decode(last_json)
    assert.are.equal("char", msg.selection.mode)
    assert.are.equal(5, msg.selection.ec)
  end)

  it("sends `false` — not an absent key — when the selection is gone", function()
    leave_visual()
    selection_sync.reset()
    last_json = nil
    selection_sync.send_current_selection(buf)
    -- vim.json.encode drops nil-valued keys; the client has to be TOLD, or it
    -- keeps drawing the selection that is no longer there.
    assert.are.equal(false, vim.json.decode(last_json).selection)
  end)

  it("does not repeat an unchanged selection", function()
    leave_visual()
    selection_sync.reset()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v4l")
    selection_sync.send_current_selection(buf)
    last_json = nil
    selection_sync.send_current_selection(buf)
    leave_visual()
    assert.is_nil(last_json)
  end)

  it("clears the highlight when the feature is switched off", function()
    leave_visual()
    selection_sync.reset()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v4l")
    selection_sync.send_current_selection(buf)
    bcfg.defaults.selection_sync = false
    last_json = nil
    selection_sync.send_current_selection(buf)
    leave_visual()
    bcfg.defaults.selection_sync = true
    assert.are.equal(false, vim.json.decode(last_json).selection)
  end)

  ws.send_control = orig_send_control
end)

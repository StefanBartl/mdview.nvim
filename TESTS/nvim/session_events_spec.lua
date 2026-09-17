---@module 'tests.nvim.session_events_spec'
-- Verifies mdview.core.session (buffer-content snapshot store + its naive
-- compute_line_diff) and mdview.core.events (push_buffer / store_snapshot_on_enter).
-- Both are dormant -- superseded by live_push.lua / bufenter.lua on the live
-- session path (see core/events.lua's own module docstring) -- but still real,
-- reachable, requireable logic with no coverage at all before this. ws_client
-- is stubbed so push_buffer's sends are observable instead of shelling out.

---@diagnostic disable: undefined-global, duplicate-set-field

local session = require("mdview.core.session")
local events = require("mdview.core.events")
local ws = require("mdview.adapter.ws_client")

local sent_payloads
local orig_send_markdown = ws.send_markdown
ws.send_markdown = function(path, markdown, opts)
  sent_payloads = sent_payloads or {}
  sent_payloads[#sent_payloads + 1] = { path = path, markdown = markdown, opts = opts }
end

describe("core.session store/get/init/shutdown", function()
  it("get() is nil for a path never stored", function()
    session.init()
    assert.is_nil(session.get("/never/stored.md"))
  end)

  it("store() normalizes the path and records a hash + the lines", function()
    session.init()
    session.store("C:\\proj\\notes.md", { "a", "b" })
    local entry = session.get("C:/proj/notes.md")
    assert(entry, "expected an entry under the normalized (forward-slash) path")
    assert.are.same({ "a", "b" }, entry.lines)
    assert(entry.hash and #entry.hash > 0, "expected a computed hash")
  end)

  it("shutdown() clears every stored buffer", function()
    session.store("/a.md", { "x" })
    session.shutdown()
    assert.is_nil(session.get("/a.md"))
  end)

  it("init() also clears (used at session start, not just teardown)", function()
    session.store("/b.md", { "x" })
    session.init()
    assert.is_nil(session.get("/b.md"))
  end)
end)

describe("core.session.compute_line_diff", function()
  it("treats nil old_lines as a full replace covering every new line", function()
    local diff = session.compute_line_diff(nil, { "a", "b", "c" })
    assert.are.equal(1, #diff)
    assert.are.equal(1, diff[1].start)
    assert.are.equal(3, diff[1]["end"])
    assert.are.same({ "a", "b", "c" }, diff[1].lines)
  end)

  it("returns an empty list when nothing changed", function()
    assert.are.same({}, session.compute_line_diff({ "a", "b" }, { "a", "b" }))
  end)

  it("finds a single differing line in the middle", function()
    local diff = session.compute_line_diff({ "a", "b", "c" }, { "a", "X", "c" })
    assert.are.equal(1, #diff)
    assert.are.equal(2, diff[1].start)
    assert.are.equal(2, diff[1]["end"])
    assert.are.same({ "X" }, diff[1].lines)
  end)

  it("covers a growing tail when new_lines is longer", function()
    local diff = session.compute_line_diff({ "a", "b" }, { "a", "b", "c", "d" })
    assert.are.equal(1, #diff)
    assert.are.equal(3, diff[1].start)
    assert.are.same({ "c", "d" }, diff[1].lines)
  end)
end)

describe("core.events.push_buffer", function()
  it("is a no-op for a non-markdown buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "mdview_spec_events_plain.lua")
    vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })
    sent_payloads = nil
    events.push_buffer(buf, true)
    assert.is_nil(sent_payloads)
  end)

  it("is a no-op for an unnamed buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    sent_payloads = nil
    events.push_buffer(buf, true)
    assert.is_nil(sent_payloads)
  end)

  it("force=true sends the whole buffer as one replace chunk", function()
    session.shutdown()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "mdview_spec_events_force.md")
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })

    sent_payloads = nil
    events.push_buffer(buf, true)

    assert.are.equal(1, #sent_payloads)
    assert.are.equal("one\ntwo", sent_payloads[1].markdown)
    assert.is_true(sent_payloads[1].opts.immediate)
  end)

  it("BUG: a same-length single-line edit sends NOTHING (diff_granular drops it)", function()
    -- push_buffer's non-force path diffs against the last snapshot with
    -- utils/diff_granular (see that module's own docstring: "a buggy Myers
    -- attempt that dropped real changes", pinned in isolation in
    -- TESTS/lua/diff_granular_spec.lua). This is the concrete fallout one
    -- layer up: a same-length replacement -- the single most common kind of
    -- edit -- produces zero diff edits, so the for-loop below never calls
    -- ws_client.send_markdown at all. If core/events.lua is ever reactivated
    -- (see its module docstring) this would have to move to utils/line_diff
    -- first, exactly as the live push path (bindings/autocmds/live_push.lua)
    -- already does.
    session.shutdown()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "mdview_spec_events_diff.md")
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
    events.push_buffer(buf, true) -- establish the baseline snapshot

    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "TWO-EDITED" })
    sent_payloads = nil
    events.push_buffer(buf, false)

    assert.is_nil(sent_payloads) -- BUG: "TWO-EDITED" is never sent anywhere
  end)

  it("BUG: a pure append is not dropped, but sends the WRONG line", function()
    -- diff_granular does emit an edit here (op="insert", start=0, count=1,
    -- lines={"three"}) -- unlike the same-length case above. But push_buffer
    -- extracts the chunk to send via
    --   vim.list_slice(new_lines, d.start+1, d.start+(d.count or #new_lines))
    -- which for an insert reads d.count=1 as "one line wide starting at
    -- d.start" in NEW-LINES coordinates -- landing on new_lines[1] ("one")
    -- instead of the actually-inserted d.lines ("three"). Two independent
    -- bugs compound here: diff_granular's count=1 convention for inserts,
    -- and events.lua trusting position+count over the edit's own `lines`.
    session.shutdown()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "mdview_spec_events_diff_append.md")
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })
    events.push_buffer(buf, true)

    vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "three" }) -- append, not a same-length edit
    sent_payloads = nil
    events.push_buffer(buf, false)

    assert.are.equal(1, #sent_payloads)
    assert.are.equal("one", sent_payloads[1].markdown) -- BUG: should be "three"
  end)
end)

describe("core.events.store_snapshot_on_enter", function()
  it("stores a snapshot only once (does not overwrite an existing one)", function()
    session.shutdown()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "mdview_spec_events_enter.md")
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first" })

    events.store_snapshot_on_enter(buf)
    local path = require("mdview.helper.normalize").path(vim.api.nvim_buf_get_name(buf))
    assert.are.same({ "first" }, session.get(path).lines)

    -- Change the buffer WITHOUT going through push_buffer, then "enter"
    -- again: the existing snapshot must be left alone (it only seeds when
    -- there is no prior entry for this path).
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "second" })
    events.store_snapshot_on_enter(buf)
    assert.are.same({ "first" }, session.get(path).lines)
  end)

  it("is a no-op for a non-markdown buffer", function()
    session.shutdown()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "mdview_spec_events_enter_plain.lua")
    vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })
    events.store_snapshot_on_enter(buf)
    local path = require("mdview.helper.normalize").path(vim.api.nvim_buf_get_name(buf))
    assert.is_nil(session.get(path))
  end)
end)

session.shutdown()
ws.send_markdown = orig_send_markdown

---@module 'tests.nvim.fence_spans_spec'
-- The Neovim half of `browser.highlighter = "nvim"`: turning color_my_ascii's
-- applied highlighting into the payload the browser paints from.
--
-- color_my_ascii is a soft dependency and is not on this suite's runtimepath,
-- so it is stubbed here. That is not a shortcut — it is the point: what needs
-- guarding is the *translation* (byte columns, byte lengths, which blocks are
-- worth sending at all), and a stub pins those against a known input in a way
-- the real plugin's colorscheme-dependent output never could.
--
-- The client half is covered in TESTS/client/nvimHighlight.test.ts.

---@diagnostic disable: undefined-global, need-check-nil, duplicate-set-field

local ws = require("mdview.adapter.ws_client")
local state = require("mdview.core.state")
local bcfg = require("mdview.config.browser")

--- Install a fake color_my_ascii whose blocks/runs are given verbatim.
---@param blocks table[] what fences.list_blocks returns
---@param runs_by_block table<integer, table> block index -> runs_for_block result
---@param attrs table<string, table> group -> attributes
local function stub_cma(blocks, runs_by_block, attrs)
  local index_of = {}
  for i, b in ipairs(blocks) do
    index_of[b] = i
  end
  package.loaded["color_my_ascii"] = {
    fences = {
      list_blocks = function()
        return blocks
      end,
    },
    highlight = {
      runs_for_block = function(_, block)
        return runs_by_block[index_of[block]] or {}
      end,
      attrs_for_group = function(group)
        return attrs[group] or {}
      end,
    },
  }
  package.loaded["mdview.core.fence_spans"] = nil
  return require("mdview.core.fence_spans")
end

local function clear_cma()
  package.loaded["color_my_ascii"] = nil
  package.loaded["mdview.core.fence_spans"] = nil
end

local ATTRS = {
  Keyword = { fg = "#af87af", bold = true },
  Ident = { fg = "#d75f87" },
  Plain = {}, -- a group that resolves to nothing renderable
}

describe("fence_spans.collect", function()
  it("reports columns as 1-based byte columns and lengths in bytes", function()
    local blocks = { { content_start = 5 } } -- 0-indexed -> first content line 6
    local runs = {
      [1] = {
        { { text = "local", group = "Keyword" }, { text = " ", group = nil }, { text = "M", group = "Ident" } },
      },
    }
    local spans = stub_cma(blocks, runs, ATTRS)
    local payload = spans.collect(0)
    clear_cma()

    assert.are.equal(1, payload.v)
    assert.are.equal(1, #payload.blocks)
    assert.are.equal(6, payload.blocks[1].line)

    local row = payload.blocks[1].rows[1]
    assert.are.equal(2, #row) -- the unhighlighted gap is not a span
    assert.are.same({ c = 1, n = 5, f = "#af87af", b = true }, row[1])
    assert.are.same({ c = 7, n = 1, f = "#d75f87" }, row[2])
  end)

  it("counts a multi-byte character by its bytes", function()
    local blocks = { { content_start = 0 } }
    local runs = { [1] = { { { text = "-- ", group = nil }, { text = "ä", group = "Ident" } } } }
    local spans = stub_cma(blocks, runs, ATTRS)
    local payload = spans.collect(0)
    clear_cma()

    local span = payload.blocks[1].rows[1][1]
    assert.are.equal(4, span.c) -- after three ASCII bytes
    assert.are.equal(2, span.n) -- "ä" is two bytes
  end)

  it("omits a block whose groups resolve to nothing renderable", function()
    -- The consumer must fall through to its own highlighter for these, so
    -- sending an empty block would be worse than sending none.
    local blocks = { { content_start = 0 }, { content_start = 9 } }
    local runs = {
      [1] = { { { text = "plain", group = "Plain" } } },
      [2] = { { { text = "local", group = "Keyword" } } },
    }
    local spans = stub_cma(blocks, runs, ATTRS)
    local payload = spans.collect(0)
    clear_cma()

    assert.are.equal(1, #payload.blocks)
    assert.are.equal(10, payload.blocks[1].line)
  end)

  it("is nil when nothing is painted at all", function()
    local blocks = { { content_start = 0 } }
    local runs = { [1] = { { { text = "plain", group = nil } } } }
    local spans = stub_cma(blocks, runs, ATTRS)
    local payload = spans.collect(0)
    clear_cma()

    assert.is_nil(payload)
  end)

  it("is nil without color_my_ascii, rather than erroring", function()
    clear_cma()
    local spans = require("mdview.core.fence_spans")
    assert.is_nil(spans.collect(0))
    package.loaded["mdview.core.fence_spans"] = nil
  end)
end)

describe("fence_spans.push", function()
  local sent
  local orig_send_spans = ws.send_spans
  ws.send_spans = function(_, json)
    sent = json
  end

  local blocks = { { content_start = 0 } }
  local runs = { [1] = { { { text = "local", group = "Keyword" } } } }

  it("sends nothing under a highlighter that does not consume it", function()
    local spans = stub_cma(blocks, runs, ATTRS)
    state.set_server({ stub = true })
    bcfg.defaults.highlighter = "hljs"
    sent = nil
    spans.push(0, "room.md")
    assert.is_nil(sent)
    clear_cma()
  end)

  it("sends the payload under highlighter = nvim", function()
    local spans = stub_cma(blocks, runs, ATTRS)
    bcfg.defaults.highlighter = "nvim"
    sent = nil
    spans.push(0, "room.md")
    bcfg.defaults.highlighter = "hljs"
    clear_cma()

    local json = assert(sent, "a payload was sent")
    assert.are.equal(1, vim.json.decode(json).v)
  end)

  ws.send_spans = orig_send_spans
end)

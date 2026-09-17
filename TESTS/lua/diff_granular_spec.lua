---@module 'tests.lua.diff_granular_spec'
-- mdview.utils.diff_granular's own module docstring already calls it "a buggy
-- Myers attempt that dropped real changes" and says utils/line_diff.lua (the
-- module actually on the live push path — see core/events.lua's docstring for
-- why this one is dormant) was written to replace it for exactly that reason.
-- No test ever pinned what "dropped real changes" means concretely, so this
-- does: a same-length single-line replacement produces NO edits at all,
-- meaning a naive apply (delete old / insert new by index) reproduces the OLD
-- content, not the new one.
--
-- BUG: kept as a pinned regression, not fixed here. The module is dormant
-- (only reachable through core/events.lua, itself unwired -- see that file's
-- docstring) and superseded by utils/line_diff.lua, which core/events.lua
-- would need to be ported to before this backtrace is worth repairing.

---@diagnostic disable: undefined-global

local assert = require("luassert")
local diff = require("mdview.utils.diff_granular")

--- Apply `edits` (op="delete"|"insert", 0-based `start`, `count`, `lines`) to
--- `old`, the same way a consumer reassembling from these ops would.
---@param old string[]
---@param edits table[]
---@return string[]
local function apply(old, edits)
  local out = {}
  for i = 1, #old do
    out[i] = old[i]
  end
  local offset = 0
  for _, e in ipairs(edits) do
    local pos = e.start + offset
    if e.op == "delete" then
      table.remove(out, pos + 1)
      offset = offset - 1
    elseif e.op == "insert" then
      table.insert(out, pos + 1, e.lines[1])
      offset = offset + 1
    end
  end
  return out
end

describe("diff_granular (BUG: drops same-length single-line replacements)", function()
  it("produces zero edits for a single-line replacement in the middle", function()
    local old = { "a", "b", "c" }
    local new = { "a", "x", "c" }
    local edits = diff(old, new)

    -- BUG: a real change exists (line 2), but the backtrace emits nothing.
    assert.are.equal(0, #edits)
  end)

  it("applying the (empty) edit set reproduces the OLD content, not the new one", function()
    local old = { "a", "b", "c" }
    local new = { "a", "x", "c" }
    local edits = diff(old, new)
    local got = apply(old, edits)

    -- BUG: this is the concrete failure mode -- a consumer trusting these
    -- edits ends up with the stale line still in place, not the new one.
    assert.are.same(old, got)
    assert.are.equal("b", got[2]) -- still the old line; "x" never arrives
  end)

  it("also drops a same-length replacement in a longer document", function()
    local old = { "1", "2", "3", "4", "5" }
    local new = { "1", "9", "9", "4", "5" }
    local edits = diff(old, new)
    assert.are.equal(0, #edits)
  end)

  it("also drops a pure trailing delete -- not just replacements", function()
    -- Not confined to replacements: this is a plain "the last line is gone"
    -- edit (old has one more line than new, otherwise identical), which
    -- utils/line_diff.lua's common-suffix scan gets right trivially. The
    -- backtrace here still emits nothing.
    local old = { "a", "b", "c" }
    local new = { "a", "b" }
    local edits = diff(old, new)
    assert.are.equal(0, #edits)
  end)

  it("also drops a pure insert into an empty document", function()
    local old = {}
    local new = { "a" }
    local edits = diff(old, new)
    assert.are.equal(0, #edits)
  end)
end)

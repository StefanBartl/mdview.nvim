---@module 'tests.lua.copy_lines_spec'
-- mdview.helper.copy_lines: a shallow array copy used on the live push path
-- (bindings/autocmds/bufenter.lua's BufEnter snapshot) and by the dormant
-- core/events.lua. Untouched by round 25 and unmentioned in TESTS/README's
-- omitted list -- simply missed, not deliberately excluded: it is a small
-- pure-Lua module with a real branch (lib.nvim's clone vs. a local fallback
-- loop) and no `vim` global, so it belongs here rather than TESTS/nvim/.
--
-- Both branches have to actually return an independent copy, not the same
-- table reference: bufenter.lua snapshots a buffer's lines specifically so a
-- later diff has something stable to compare against, which breaks silently
-- (comparing a table against itself) if either branch ever aliased instead
-- of copying.

---@diagnostic disable: undefined-global

local assert = require("luassert")

describe("copy_lines (lib.nvim clone available)", function()
  -- The default state: lib.nvim is resolvable via .busted's lpath (a real
  -- sibling checkout), so this exercises the `has_lib_clone` branch as it
  -- runs in production for every real user (mdview.nvim hard-depends on
  -- lib.nvim -- see init.lua's own startup guard).
  local copy_lines = require("mdview.helper.copy_lines")

  it("returns a new array with the same elements in the same order", function()
    local original = { "one", "two", "three" }
    local copy = copy_lines(original)
    assert.are.same(original, copy)
  end)

  it("returns a different table, not the same reference", function()
    local original = { "a", "b" }
    local copy = copy_lines(original)
    assert.is_false(copy == original)
  end)

  it("is independent of the original after mutation (real copy, not an alias)", function()
    local original = { "first", "second" }
    local copy = copy_lines(original)
    copy[1] = "mutated"
    table.insert(copy, "third")
    assert.are.equal("first", original[1])
    assert.are.equal(2, #original)
    assert.are.equal("mutated", copy[1])
    assert.are.equal(3, #copy)
  end)

  it("copies an empty array to an empty array", function()
    assert.are.same({}, copy_lines({}))
  end)
end)

describe("copy_lines (lib.nvim clone unavailable -- local fallback loop)", function()
  -- copy_lines.lua's `has_lib_clone` is resolved ONCE at module load (a
  -- top-level `pcall(require, "lib.lua.tables")`), so the fallback branch can
  -- only be exercised by blocking that require BEFORE the module is first
  -- loaded, then forcing a fresh require. package.preload is the standard
  -- way to make a require() fail for a module that already resolves fine on
  -- disk (a real sibling lib.nvim checkout, in this suite).
  local mod_name = "lib.lua.tables"
  local target = "mdview.helper.copy_lines"

  local cached_lib = package.loaded[mod_name]
  local cached_target = package.loaded[target]
  package.loaded[mod_name] = nil
  package.loaded[target] = nil
  package.preload[mod_name] = function()
    error("simulated: lib.lua.tables unavailable")
  end

  local copy_lines = require(target)

  package.preload[mod_name] = nil
  package.loaded[mod_name] = cached_lib
  package.loaded[target] = cached_target

  it("still returns a correct, independent copy via the local loop", function()
    local original = { "x", "y", "z" }
    local copy = copy_lines(original)
    assert.are.same(original, copy)
    assert.is_false(copy == original)
    copy[1] = "changed"
    assert.are.equal("x", original[1])
  end)

  it("still copies an empty array correctly", function()
    assert.are.same({}, copy_lines({}))
  end)
end)

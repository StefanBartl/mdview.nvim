---@module 'tests.lua.smoke_spec'
-- Minimal busted smoke test for Lua suite.

local assert = require("luassert")

describe("smoke - lua", function()
  it("basic equality works", function()
    assert.are.equal(1, 1)
  end)
end)

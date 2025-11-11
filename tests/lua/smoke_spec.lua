---@module 'tests.lua.smoke_spec'
-- Minimal busted smoke test for Lua suite.

---@diagnostic disable: undefined-global

local assert = require("luassert")

describe("smoke test", function()
  it("Should be true", function()
		assert.is._true(true)
  end)
end)

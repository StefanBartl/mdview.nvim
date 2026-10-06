---@module 'tests.nvim.spotlight_mirror_spec'
-- Covers core/spotlight_mirror.lua: turning spotlight.nvim's read API into the
-- payload the preview paints, and saying "nothing to mirror" when spotlight.nvim
-- is not there. spotlight.nvim itself is replaced by a stub -- it is an optional
-- dependency, and the point is exactly what happens with and without it.

---@diagnostic disable: undefined-global, need-check-nil, duplicate-set-field

local mirror = require("mdview.core.spotlight_mirror")
local cfg = require("mdview.config")

local original = package.loaded["spotlight"]

--- Install a stub facade; returns the table so a spec can record the calls.
---@param items table[]
---@param palette table[]|nil
---@return table stub
local function stub(items, palette)
  local s = { calls = {} }
  s.spotlights = function(opts)
    s.calls[#s.calls + 1] = opts
    return vim.deepcopy(items)
  end
  s.colors = function()
    return vim.deepcopy(palette or {})
  end
  package.loaded["spotlight"] = s
  return s
end

describe("spotlight_mirror", function()
  before_each(function()
    cfg.defaults.browser.spotlight_max_matches = 500
  end)

  after_each(function()
    package.loaded["spotlight"] = original
  end)

  describe("without spotlight.nvim", function()
    it("builds nothing instead of failing", function()
      package.loaded["spotlight"] = nil
      -- Make sure a real checkout on the runtimepath cannot answer the require.
      package.preload["spotlight"] = function()
        error("module 'spotlight' not found")
      end
      assert.is_nil(mirror.plugin())
      assert.is_nil(mirror.build())
      package.preload["spotlight"] = nil
    end)

    it("treats a spotlight.nvim without the read API as absent", function()
      package.loaded["spotlight"] = { setup = function() end }
      assert.is_nil(mirror.plugin())
      assert.is_nil(mirror.build())
    end)

    it("survives a read API that raises", function()
      package.loaded["spotlight"] = {
        spotlights = function()
          error("boom")
        end,
      }
      assert.is_nil(mirror.build())
    end)
  end)

  describe("build", function()
    it("asks for whole-file spotlights only", function()
      local s = stub({})
      mirror.build()
      assert.are.same({ { whole_file = true } }, s.calls)
    end)

    it("maps each spotlight to the browser's item shape", function()
      stub({
        { text = "SYSsystosca", slot = 3, line_mode = false, kind = "word", ignore_case = false },
        { text = "400 (Bad Request)", slot = 5, line_mode = true, kind = "literal", ignore_case = true },
      })
      local payload = mirror.build()
      assert.are.equal("spotlight", payload.type)
      assert.are.same({
        { text = "SYSsystosca", slot = 3, line = false, kind = "word", ignoreCase = false },
        { text = "400 (Bad Request)", slot = 5, line = true, kind = "literal", ignoreCase = true },
      }, payload.items)
    end)

    it("accepts the `line` alias and defaults an unknown kind to a plain substring", function()
      stub({ { text = "x", slot = 1, line = true } })
      local item = mirror.build().items[1]
      assert.is_true(item.line)
      assert.are.equal("literal", item.kind)
      assert.is_false(item.ignoreCase) -- case-sensitive unless told otherwise
    end)

    it("drops empty texts and texts too long to send, and says it did", function()
      stub({
        { text = "", slot = 1 },
        { text = "ok", slot = 2 },
        { text = string.rep("a", mirror.MAX_TEXT_BYTES + 1), slot = 3 },
      })
      local payload = mirror.build()
      assert.are.equal(1, #payload.items)
      assert.are.equal("ok", payload.items[1].text)
      assert.is_true(payload.capped)
    end)

    it("stops at MAX_ITEMS", function()
      local many = {}
      for i = 1, mirror.MAX_ITEMS + 5 do
        many[i] = { text = "t" .. i, slot = (i % 8) + 1 }
      end
      stub(many)
      local payload = mirror.build()
      assert.are.equal(mirror.MAX_ITEMS, #payload.items)
      assert.is_true(payload.capped)
    end)

    it("carries the live palette and keeps only well-formed colors", function()
      stub({}, {
        { slot = 1, group = "Spotlight1", fg = "#112233", bg = "#aabbcc", bold = true },
        { slot = 2, group = "Spotlight2", fg = "red", bg = "#aabbccdd", bold = false },
      })
      local colors = mirror.build().colors
      assert.are.same({ slot = 1, fg = "#112233", bg = "#aabbcc", bold = true }, colors[1])
      assert.is_nil(colors[2].fg) -- a color name is not a "#rrggbb": never forwarded
      assert.are.equal("#aabbccdd", colors[2].bg)
    end)

    it("builds with no palette when the plugin has no colors()", function()
      package.loaded["spotlight"] = {
        spotlights = function()
          return { { text = "x", slot = 1 } }
        end,
      }
      local payload = mirror.build()
      assert.are.equal(1, #payload.items)
      assert.are.same({}, payload.colors)
    end)

    it("encodes an empty list as a JSON array, which is what the client expects", function()
      stub({})
      local json = vim.json.encode(mirror.build())
      assert.is_truthy(json:find('"items":[]', 1, true))
    end)
  end)

  describe("config defaults", function()
    it("mirrors by default, with a bounded match count", function()
      local defaults = require("mdview.config.DEFAULTS")
      assert.is_true(defaults.browser.spotlight_sync)
      assert.are.equal(500, defaults.browser.spotlight_max_matches)
    end)
  end)

  describe("max_matches", function()
    it("follows browser.spotlight_max_matches", function()
      cfg.defaults.browser.spotlight_max_matches = 42
      stub({})
      assert.are.equal(42, mirror.build().max)
    end)

    it("repairs an unusable value to the default", function()
      for _, bad in ipairs({ 0, -3, "lots", false, math.huge }) do
        cfg.defaults.browser.spotlight_max_matches = bad
        assert.are.equal(mirror.DEFAULT_MAX_MATCHES, mirror.max_matches())
      end
      cfg.defaults.browser.spotlight_max_matches = 12.9
      assert.are.equal(12, mirror.max_matches())
    end)
  end)

  describe("empty", function()
    it("is the payload that clears the preview", function()
      local payload = mirror.empty()
      assert.are.same({}, payload.items)
      assert.are.same({}, payload.colors)
    end)
  end)
end)

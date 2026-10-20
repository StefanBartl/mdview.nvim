---@module 'tests.nvim.cursor_blink_spec'
-- core.cursor_blink: the browser.cursor_blink setting as the client takes it
-- (false, or a period in ms) and its URL parameter.

---@diagnostic disable: undefined-global

local blink = require("mdview.core.cursor_blink")

describe("cursor_blink.normalize", function()
  it("is steady (false) for nil, false, zero, negatives and junk", function()
    assert.are.equal(false, blink.normalize(nil))
    assert.are.equal(false, blink.normalize(false))
    assert.are.equal(false, blink.normalize(0))
    assert.are.equal(false, blink.normalize(-5))
    assert.are.equal(false, blink.normalize("fast"))
    assert.are.equal(false, blink.normalize({ ms = 0 }))
  end)

  it("takes the default period for true and for a table without ms", function()
    assert.are.equal(blink.DEFAULT_MS, blink.normalize(true))
    assert.are.equal(blink.DEFAULT_MS, blink.normalize({}))
  end)

  it("takes a number or { ms = n } as the period, rounded", function()
    assert.are.equal(300, blink.normalize(300))
    assert.are.equal(250, blink.normalize({ ms = 250 }))
    assert.are.equal(401, blink.normalize(400.6))
  end)
end)

describe("cursor_blink.url_param", function()
  it("is empty while steady and &blink=<ms> when on", function()
    assert.are.equal("", blink.url_param({ cursor_blink = false }))
    assert.are.equal("", blink.url_param({}))
    assert.are.equal("&blink=530", blink.url_param({ cursor_blink = true }))
    assert.are.equal("&blink=120", blink.url_param({ cursor_blink = { ms = 120 } }))
  end)
end)

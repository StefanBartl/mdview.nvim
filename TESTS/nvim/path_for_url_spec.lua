---@module 'tests.nvim.path_for_url_spec'
-- Verifies normalize.path_for_url percent-encodes ":" and "/" so a Windows
-- path never leaves a bare drive letter ("C:") in the emitted URL. That bare
-- "C:" is what made Windows' rundll32 FileProtocolHandler refuse to open the
-- :MDView start preview tab (it read the drive letter as a file reference),
-- while :MDView standalone — whose Go side url.QueryEscape's the key — worked.

---@diagnostic disable: undefined-global

local normalize = require("mdview.helper.normalize")

describe("normalize.path_for_url encodes drive letters", function()
  it("percent-encodes the ':' after a Windows drive letter", function()
    local out = normalize.path_for_url("C:/Users/x/a.md")
    -- No bare "C:" survives — that's the whole point of the fix.
    assert(not out:find("C:", 1, true), "encoded URL still contains a bare 'C:': " .. out)
    assert(out:find("C%%3[aA]"), "expected the ':' to be percent-encoded, got: " .. out)
  end)

  it("percent-encodes path separators", function()
    local out = normalize.path_for_url("C:/Users/x/a.md")
    assert(not out:find("/", 1, true), "encoded URL still contains a raw '/': " .. out)
    assert(out:find("%%2[fF]"), "expected '/' to be percent-encoded, got: " .. out)
  end)

  it("round-trips back to the original path via uri_decode", function()
    local path = "C:/Users/bartl/AppData/Local/Temp/mdv.md"
    local decoded = vim.uri_decode(normalize.path_for_url(path))
    -- The relay decodes the query param exactly once; the room key must be
    -- unchanged by the stronger encoding.
    assert.are.equal(path, decoded)
  end)

  it("normalizes backslashes before encoding", function()
    local out = normalize.path_for_url("C:\\Users\\x\\a.md")
    assert.are.equal("C:/Users/x/a.md", vim.uri_decode(out))
  end)

  it("returns nil for a nil path", function()
    assert.is_nil(normalize.path_for_url(nil))
  end)
end)

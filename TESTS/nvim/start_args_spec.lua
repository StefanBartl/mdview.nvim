---@module 'tests.nvim.start_args_spec'
-- Verifies the pure token-parsing half of :MDView start / :MDView toggle
-- (mdview.bindings.usrcmds.start's parse_start_args, exposed as
-- M._parse_start_args for exactly this -- the rest of M.run() spawns a real
-- server process and is not exercised here, see TESTS/README.md). No
-- coverage existed for this parsing logic at all before.

---@diagnostic disable: undefined-global

local start = require("mdview.bindings.usrcmds.start")
local parse = start._parse_start_args

describe("usrcmds.start._parse_start_args", function()
  it("returns nothing for an empty arg list", function()
    local file, cwd, port = parse({})
    assert.is_nil(file)
    assert.is_nil(cwd)
    assert.is_nil(port)
  end)

  it("treats the first non-cwd=/port= token as the file", function()
    local file, cwd, port = parse({ "notes.md" })
    assert.are.equal("notes.md", file)
    assert.is_nil(cwd)
    assert.is_nil(port)
  end)

  it("parses cwd= after the file", function()
    local file, cwd = parse({ "notes.md", "cwd=C:/Users/bartl/" })
    assert.are.equal("notes.md", file)
    assert.are.equal("C:/Users/bartl/", cwd)
  end)

  it("parses cwd= before the file (order-independent)", function()
    local file, cwd = parse({ "cwd=C:/Users/bartl/", "notes.md" })
    assert.are.equal("notes.md", file)
    assert.are.equal("C:/Users/bartl/", cwd)
  end)

  it("strips matching double quotes from the cwd value", function()
    local _, cwd = parse({ 'cwd="c:/Users/bartl/"' })
    assert.are.equal("c:/Users/bartl/", cwd)
  end)

  it("strips matching single quotes from the cwd value", function()
    local _, cwd = parse({ "cwd='c:/Users/bartl/'" })
    assert.are.equal("c:/Users/bartl/", cwd)
  end)

  it("parses port= as a number", function()
    local _, _, port = parse({ "port=8080" })
    assert.are.equal(8080, port)
  end)

  it("parses file + cwd= + port= together, in any order", function()
    local file, cwd, port = parse({ "port=8080", "notes.md", "cwd=/tmp/proj" })
    assert.are.equal("notes.md", file)
    assert.are.equal("/tmp/proj", cwd)
    assert.are.equal(8080, port)
  end)

  it("only the FIRST non-prefixed token becomes the file; later ones are ignored", function()
    local file = parse({ "first.md", "second.md" })
    assert.are.equal("first.md", file)
  end)

  it("handles a nil fargs list without erroring", function()
    local ok, file, cwd, port = pcall(parse, nil)
    assert.is_true(ok)
    assert.is_nil(file)
    assert.is_nil(cwd)
    assert.is_nil(port)
  end)

  it("rejects a malformed port= instead of adopting it as the file", function()
    -- `808O` (letter O): before the fix this became the FILE path, the relay
    -- started on the default port, and an empty document was previewed.
    local file, cwd, port, err = parse({ "port=808O" })
    assert.is_nil(file)
    assert.is_nil(cwd)
    assert.is_nil(port)
    assert.is_true(type(err) == "string" and err:find("port=", 1, true) ~= nil)
  end)

  it("rejects a bare cwd= / port= with no value", function()
    local _, _, _, err_cwd = parse({ "notes.md", "cwd=" })
    assert.is_true(type(err_cwd) == "string" and err_cwd:find("cwd=", 1, true) ~= nil)
    local _, _, _, err_port = parse({ "port=", "notes.md" })
    assert.is_true(type(err_port) == "string" and err_port:find("port=", 1, true) ~= nil)
  end)

  it("returns no error for well-formed args", function()
    local _, _, _, err = parse({ "notes.md", "cwd=/tmp/proj", "port=8080" })
    assert.is_nil(err)
  end)
end)

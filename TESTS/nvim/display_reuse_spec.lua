---@module 'tests.nvim.display_reuse_spec'
-- The line-wise reuse of a translation around an edit (`core/display.lua`,
-- `_reuse_translation`) and the guard that says when it is NOT allowed.
--
-- An edit pushes every 150 ms, and the parse that would answer it (the cache-only
-- step of `translate_markdown`) reads the WHOLE document: about 0.4 s at 20 000
-- lines. So a plain edit is answered by a comparison of lines (the translation
-- around the edit is kept, the edited lines are original), and only an edit that
-- can change what the lines around it ARE takes the parse: a fence, a math block,
-- an HTML block, a heading (in-page links follow the translated heading slugs), a
-- setext underline, the head of the document (front matter).
--
-- The cases stand for facts of language.nvim's segmenter (segment.lua), e.g. that
-- everything below `<pre>`, `<script>`, `<style>`, `<textarea>` or `<?` is literal
-- up to its end tag, that a block tag such as `<div>` is literal up to the next
-- blank line, that a lone tag line only starts an HTML block when no paragraph is
-- open, and that a paragraph above `===` or `---` is a heading. The function is
-- pure: `out` marks every non-blank line with "T:", so a line that kept its old
-- translation is told from the edit itself.
--
-- What is NOT scanned is pinned as much as what is: the lines around an edit are
-- not part of it (a parse per keystroke under every heading costs more than the
-- stale lines it avoids).

---@diagnostic disable: undefined-global

local reuse = require("mdview.core.display")._reuse_translation

--- The translation of `lines` as these specs see it.
---@param lines string[]
---@return string[]
local function mark(lines)
  local out = {}
  for i, l in ipairs(lines) do
    out[i] = l:match("^%s*$") and l or ("T:" .. l)
  end
  return out
end

---@param lines string[]
---@param i integer
---@param text string
---@return string[]
local function with(lines, i, text)
  local c = vim.list_slice(lines)
  c[i] = text
  return c
end

---@param lines string[]
---@param i integer
---@param text string
---@return string[]
local function inserted(lines, i, text)
  local c = vim.list_slice(lines)
  table.insert(c, i, text)
  return c
end

---@param lines string[]
---@param i integer
---@return string[]
local function removed(lines, i)
  local c = vim.list_slice(lines)
  table.remove(c, i)
  return c
end

--- Reuse the translation of `old` for `new`: the text, or nil when the guard refuses.
---@param old string[]
---@param new string[]
---@return string[]|nil
local function try(old, new)
  return reuse(old, mark(old), new)
end

-- Line 4 of this document is the one the cases edit: the edit starts below the head.
local DOC = { "kopf", "", "eins", "zwei", "", "drei", "vier" }

describe("display reuse: a plain edit keeps the translation around it", function()
  it("an edit in the middle: the lines around it keep their translation, the edit is the original", function()
    assert.are.same({ "T:kopf", "", "T:eins", "zwei!", "", "T:drei", "T:vier" }, try(DOC, with(DOC, 4, "zwei!")))
  end)

  it("an inserted and a removed line", function()
    assert.are.same(
      { "T:kopf", "", "T:eins", "neu", "T:zwei", "", "T:drei", "T:vier" },
      try(DOC, inserted(DOC, 4, "neu"))
    )
    assert.are.same({ "T:kopf", "", "T:eins", "", "T:drei", "T:vier" }, try(DOC, removed(DOC, 4)))
  end)

  it("an appended line and no change at all", function()
    assert.are.same(
      { "T:kopf", "", "T:eins", "T:zwei", "", "T:drei", "T:vier", "neu" },
      try(DOC, inserted(DOC, 8, "neu"))
    )
    assert.are.same(mark(DOC), try(DOC, vim.list_slice(DOC)))
  end)

  it("typing into the blank line under a heading: the heading is a neighbour, not part of the edit", function()
    local doc = { "kopf", "", "# Titel", "", "eins", "", "zwei" }
    assert.are.same({ "T:kopf", "", "T:# Titel", "neu", "T:eins", "", "T:zwei" }, try(doc, with(doc, 4, "neu")))
  end)

  it("an edit in the first line of a code block: the fence lines around it are neighbours", function()
    local doc = { "kopf", "", "```", "code", "```", "", "text" }
    assert.are.same({ "T:kopf", "", "T:```", "code2", "T:```", "", "T:text" }, try(doc, with(doc, 4, "code2")))
  end)

  it("an edit directly below a $$ or a <!-- line, or above its closer, is plain", function()
    local math = { "kopf", "", "$$", "x = 1", "$$", "", "text" }
    assert.are.same({ "T:kopf", "", "T:$$", "x = 2", "T:$$", "", "T:text" }, try(math, with(math, 4, "x = 2")))
    local comment = { "kopf", "", "<!--", "note", "-->", "", "text" }
    assert.are.same({ "T:kopf", "", "T:<!--", "note!", "T:-->", "", "T:text" }, try(comment, with(comment, 4, "note!")))
  end)

  it("an underline that a blank line separates from the edit is not its underline", function()
    local doc = { "kopf", "", "text", "", "---", "x" }
    assert.are.same({ "T:kopf", "", "text!", "", "T:---", "T:x" }, try(doc, with(doc, 3, "text!")))
  end)

  it("a plain edit inside an HTML block, and one above a lone tag line (the paragraph state stays)", function()
    local block = { "kopf", "", "<div>", "eins", "zwei", "", "drei" }
    assert.is_truthy(try(block, with(block, 4, "eins!")))
    local tag = { "kopf", "", "text", "<br>" }
    assert.is_truthy(try(tag, with(tag, 3, "text2")))
  end)

  it("typing into a blank line above a bullet item (a bullet interrupts a paragraph either way)", function()
    local doc = { "kopf", "", "", "- item" }
    assert.are.same({ "T:kopf", "", "text", "T:- item" }, try(doc, with(doc, 3, "text")))
  end)
end)

describe("display reuse: an edit that opens or closes a structure takes the parse", function()
  -- Each of these, typed into line 4 of DOC, changes what the lines below it are
  -- (or, for a heading, what in-page links point to).
  local openers = {
    "```",
    "```lua",
    "~~~",
    "$$",
    "$$ x $$",
    "<!-- c -->",
    "<!--",
    "-->",
    "<pre>",
    "<script>",
    "<style>",
    "<textarea>",
    "<details>",
    "<div>",
    "<?php",
    "?>",
    "<!DOCTYPE html>",
    "</pre>",
    "</div>",
    "  <pre>",
    "> <div>",
    "text </pre> text",
    "text </script>",
    "# Titel",
    "> # Titel",
    "===",
    "---",
    "--",
    "-",
    "> ---",
    "***",
    "* * *",
    "___",
    "+++",
    "...",
    "|---|---|",
    "| --- | --- |",
    "--- | ---",
    ":--|--:",
  }
  for _, text in ipairs(openers) do
    it(("typing %q into a paragraph"):format(text), function()
      assert.is_nil(try(DOC, with(DOC, 4, text)))
    end)
  end

  -- And the other way round: the line that held it is overwritten or deleted.
  local holders =
    { "```", "$$", "-->", "?>", "</pre>", "</div>", "# Titel", "====", "***", "<!DOCTYPE html>", "|---|---|" }
  for _, text in ipairs(holders) do
    it(("overwriting or deleting a %q line"):format(text), function()
      local old = with(DOC, 4, text)
      assert.is_nil(try(old, with(old, 4, "plain")))
      assert.is_nil(try(old, removed(old, 4)))
    end)
  end
end)

describe("display reuse: a table", function()
  local table_doc = { "kopf", "", "| a | b |", "|---|---|", "| c | d |", "| e | f |" }

  it("an edit of a header row takes the parse: the delimiter row below it decides that it is one", function()
    assert.is_nil(try(table_doc, with(table_doc, 3, "| a! | b |")))
    assert.is_nil(try(table_doc, removed(table_doc, 3)))
  end)

  it("an edit of a body row is plain", function()
    assert.are.same(
      { "T:kopf", "", "T:| a | b |", "T:|---|---|", "| c! | d |", "T:| e | f |" },
      try(table_doc, with(table_doc, 5, "| c! | d |"))
    )
  end)

  it("a line that is not a delimiter row (no pipe, or other characters) is no table rule", function()
    assert.is_truthy(try(table_doc, with(table_doc, 6, "| e | - |")))
    assert.is_truthy(try(DOC, with(DOC, 4, "a - b")))
  end)
end)

describe("display reuse: the head of the document", function()
  it("an edit of the first or the second line", function()
    assert.is_nil(try(DOC, with(DOC, 1, "kopf!")))
    assert.is_nil(try(DOC, with(DOC, 2, "x")))
    assert.is_truthy(try(DOC, with(DOC, 3, "eins!")))
  end)

  it("a front matter: the key line and the closer count, the rest of it and the body do not", function()
    local doc = { "---", "title: x", "author: y", "---", "", "text", "", "mehr" }
    assert.is_nil(try(doc, with(doc, 2, "title: z")))
    assert.is_nil(try(doc, with(doc, 4, "text")))
    assert.is_truthy(try(doc, with(doc, 3, "author: z")))
    assert.is_truthy(try(doc, with(doc, 6, "text!")))
  end)

  it("the `---` that closes a front matter is no setext underline, a thematic break of a plain document is", function()
    local doc = { "---", "title: x", "author: y", "tags: z", "---", "", "text" }
    assert.is_truthy(try(doc, with(doc, 3, "author: w")), "an edit inside the front matter is plain")
    local rule = { "---", "titel", "autor", "---", "", "text" }
    assert.is_nil(try(rule, with(rule, 3, "autor!")), "no key line: not a front matter, so an underline")
    local ended = { "---", "a: 1", "---", "text", "mehr", "---", "x" }
    assert.is_nil(try(ended, with(ended, 5, "mehr!")), "the front matter ended at line 3")
  end)

  it("a blank line before the first key line: that line decides the front matter", function()
    local doc = { "---", "", "title: x", "---", "", "text" }
    assert.is_nil(try(doc, with(doc, 3, "title")))
    assert.is_truthy(try(doc, with(doc, 6, "text!")))
  end)

  it("a +++ front matter", function()
    local doc = { "+++", "a = 1", "+++", "", "text" }
    assert.is_nil(try(doc, with(doc, 2, "a = 2")))
    assert.is_truthy(try(doc, with(doc, 5, "text!")))
  end)
end)

describe("display reuse: an edit of the text of a setext heading", function()
  it("directly above the underline", function()
    local doc = { "kopf", "", "Titel", "=====", "", "text" }
    assert.is_nil(try(doc, with(doc, 3, "Titel2")))
  end)

  it("in a heading of two lines, the underline is not directly below", function()
    local doc = { "kopf", "", "Titel", "und mehr", "-----", "", "text" }
    assert.is_nil(try(doc, with(doc, 3, "Titel2")))
    assert.is_nil(try(doc, removed(doc, 3)))
  end)

  it("with a one-dash underline", function()
    local doc = { "kopf", "", "text", "-", "x" }
    assert.is_nil(try(doc, with(doc, 3, "text!")))
  end)
end)

describe("display reuse: a blank line that is added, removed or filled", function()
  local block = { "kopf", "", "<div>", "eins", "zwei", "", "drei" }

  it("inside an HTML block it ends the block: the lines below stop being literal", function()
    assert.is_nil(try(block, with(block, 4, "")))
    assert.is_nil(try(block, inserted(block, 5, "")))
  end)

  it("behind an HTML block, text continues the block", function()
    assert.is_nil(try(block, with(block, 6, "mehr")))
    assert.is_nil(try(block, removed(block, 6)))
  end)

  it("above a lone tag line: whether the paragraph is open decides if it starts an HTML block", function()
    local doc = { "kopf", "", "", "<br>", "x" }
    assert.is_nil(try(doc, with(doc, 3, "text")))
    local filled = { "kopf", "", "text", "<br>" }
    assert.is_nil(try(filled, with(filled, 3, "")))
  end)

  it("above an indented line: a paragraph makes it a continuation, a blank line indented code", function()
    local spaces = { "kopf", "", "", "    code" }
    assert.is_nil(try(spaces, with(spaces, 3, "text")))
    local tab = { "kopf", "", "", "\tcode" }
    assert.is_nil(try(tab, with(tab, 3, "text")))
  end)
end)

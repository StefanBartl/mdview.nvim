---@module 'scripts.fuzz_reuse_guard'
--- Differential fuzz of the reuse guard of the translated preview
--- (`core/display.lua`, `_reuse_translation`) against the real segmenter of
--- language.nvim.
---
--- An edit of a translated document keeps the old translation around the edited
--- lines instead of parsing the whole document again, unless the edit can change
--- what the lines around it ARE. This script checks that claim: for a random edit
--- it asks the guard, and asks the segmenter which lines are prose and which are
--- literal before and after. A HOLE is an edit that the guard reused although a
--- line outside the edited ones changed its class. Run it whenever the guard
--- (`structural`, `head_end`, ...) or the segmenter changes.
---
---   nvim --headless -u NONE -l scripts/fuzz_reuse_guard.lua [seed] [runs] [doc.md ...]
---
---   no document   random documents of structural lines (fences, HTML, quotes,
---                 setext underlines, front matter, tables, ...): a stress test,
---                 so a lot of edits fall back
---   documents     random edits of those documents (one line replaced by another
---                 line of the same document, inserted, removed, extended)
---
--- Env: $LIB_NVIM_DIR and $LANGUAGE_NVIM_DIR (default: a checkout beside this one,
--- or `.deps/<name>`); $MAX_HOLES: exit code 1 when more holes are found than that;
--- $SHOW=1: print the edits of the first holes.
---
--- Not zero by design: the guard is a heuristic on lines, not a parser, so a
--- list item or an indented block that the edit starts can still slip through.
--- What matters is that a change makes the number worse, not that it is not 0.

local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h"))

---@param name string # repository name, e.g. "lib.nvim"
---@param marker string # a path inside it that proves it is the right one
---@return string
local function find_dep(name, marker)
  local env = vim.env[(name:upper():gsub("[^%w]", "_")) .. "_DIR"]
  local places = { env, root .. "/.deps/" .. name, vim.fs.dirname(root) .. "/" .. name }
  for _, dir in ipairs(places) do
    if dir and dir ~= "" and vim.fn.isdirectory(dir .. "/" .. marker) == 1 then
      return dir
    end
  end
  io.stderr:write(("fuzz_reuse_guard: %s not found (set $%s_DIR)\n"):format(name, (name:upper():gsub("[^%w]", "_"))))
  os.exit(2)
end

package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  find_dep("lib.nvim", "lua/lib/nvim") .. "/lua/?.lua",
  find_dep("lib.nvim", "lua/lib/nvim") .. "/lua/?/init.lua",
  find_dep("language.nvim", "lua/language") .. "/lua/?.lua",
  find_dep("language.nvim", "lua/language") .. "/lua/?/init.lua",
  package.path,
}, ";")

local reuse = require("mdview.core.display")._reuse_translation
local segment = require("language.translate.markdown.segment")

local seed = tonumber(arg[1]) or 1
local runs = tonumber(arg[2]) or 20000
local docs = {}
for i = 3, #arg do
  docs[#docs + 1] = arg[i]
end
local max_holes = tonumber(vim.env.MAX_HOLES)
math.randomseed(seed)

local PROSE = { "eins", "zwei", "drei", "vier", "Absatz fuenf", "text with `code`", "see [x](#h1)" }
-- stylua: ignore
local OTHER = {
  "# H1", "## H2", "> # QH", "```", "```lua", "~~~", "````", "$$", "$$ x $$", "price $$5",
  "<!-- c -->", "<!--", "-->", "<pre>", "</pre>", "<script>", "</script>", "<style>", "<div>",
  "</div>", "<details>", "</details>", "<?php", "?>", "<!DOCTYPE html>", "<br>", "<b>x</b> y",
  "<https://a.b>", "foo </pre> bar", "===", "---", "--", "-", "==", "***", "+++", "key: v",
  "...", "- item", "1. one", "  - sub", "* star", "> quote", "> > deep", ">", "| a | b |",
  "|---|---|", "    code", "> <div>", "> ===", "  <pre>", "<custom-tag>",
}

---@param t string[]
---@return string
local function pick(t)
  return t[math.random(#t)]
end

---@return string
local function random_line()
  local r = math.random()
  if r < 0.40 then
    return pick(PROSE)
  elseif r < 0.62 then
    return ""
  end
  return pick(OTHER)
end

--- Which lines of `lines` the segmenter translates (a prose line) and which it keeps.
---@param lines string[]
---@return boolean[]
local function classes(lines)
  local tpl = segment.segment(lines).tpl
  local c = {}
  for i = 1, #lines do
    c[i] = type(tpl[i]) == "table"
  end
  return c
end

---@param old string[]
---@return string[]
local function random_edit(old)
  local new = vim.list_slice(old)
  local r, i = math.random(), math.random(#old)
  if #docs > 0 then
    if r < 0.35 then
      new[i] = old[math.random(#old)]
    elseif r < 0.55 then
      table.insert(new, i, old[math.random(#old)])
    elseif r < 0.70 then
      table.remove(new, i)
    elseif r < 0.85 then
      table.insert(new, i, "")
    else
      new[i] = new[i]:match("^%s*$") and "neu" or (new[i] .. " neu")
    end
  elseif r < 0.6 then
    new[i] = random_line()
  elseif r < 0.8 then
    table.insert(new, i, random_line())
  elseif #new > 2 then
    table.remove(new, i)
  else
    new[1] = new[1] .. "!"
  end
  return new
end

--- The edited region as the guard sees it: `p` lines equal at the top, `s` at the bottom.
---@param old string[]
---@param new string[]
---@return integer p, integer s
local function common(old, new)
  local n, m, p = #new, #old, 0
  while p < n and p < m and new[p + 1] == old[p + 1] do
    p = p + 1
  end
  local s = 0
  while s < n - p and s < m - p and new[n - s] == old[m - s] do
    s = s + 1
  end
  return p, s
end

local stats = { edits = 0, reused = 0, fallback = 0, holes = 0 }
local shown = 0

---@param old string[]
---@param c_old boolean[]
local function try(old, c_old)
  local new = random_edit(old)
  if table.concat(new, "\n") == table.concat(old, "\n") then
    return
  end
  stats.edits = stats.edits + 1
  if not reuse(old, old, new) then
    stats.fallback = stats.fallback + 1
    return
  end
  stats.reused = stats.reused + 1
  local c_new, p, s = classes(new), common(old, new)
  local n, m = #new, #old
  local hole = false
  for i = 1, p do
    hole = hole or c_old[i] ~= c_new[i]
  end
  for k = 0, s - 1 do
    hole = hole or c_old[m - k] ~= c_new[n - k]
  end
  if hole then
    stats.holes = stats.holes + 1
    if vim.env.SHOW and shown < 12 then
      shown = shown + 1
      print("hole:\n  old " .. vim.inspect(old):gsub("%s+", " ") .. "\n  new " .. vim.inspect(new):gsub("%s+", " "))
    end
  end
end

if #docs == 0 then
  for _ = 1, runs do
    local old = {}
    for i = 1, math.random(6, 14) do
      old[i] = random_line()
    end
    try(old, classes(old))
  end
else
  for _, file in ipairs(docs) do
    local old = vim.fn.readfile(file)
    local c_old = classes(old)
    for _ = 1, runs do
      try(old, c_old)
    end
  end
end

io.stdout:write(
  ("seed %d: %d edits, %d reused, %d fell back to the parse, %d holes\n"):format(
    seed,
    stats.edits,
    stats.reused,
    stats.fallback,
    stats.holes
  )
)
io.stdout:flush()
vim.cmd(("cquit %d"):format(max_holes and stats.holes > max_holes and 1 or 0))

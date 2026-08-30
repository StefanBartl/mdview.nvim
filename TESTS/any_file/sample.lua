-- Fixture for the any_file checklist in TESTS/CHECK.md.
-- Long enough to scroll, so case 2 (proportional scroll sync) has something
-- to work with. Nothing here is loaded by the plugin.

local M = {}

--- A comment that would become a heading if the Markdown renderer ever ran
--- over this file by mistake.
---@param n integer
---@return integer
function M.double(n)
  return n * 2
end

---@param items string[]
---@return string
function M.join(items)
  return table.concat(items, ", ")
end

-- Padding below, so the buffer is taller than one screen.
local padding = {
  "line 01",
  "line 02",
  "line 03",
  "line 04",
  "line 05",
  "line 06",
  "line 07",
  "line 08",
  "line 09",
  "line 10",
  "line 11",
  "line 12",
  "line 13",
  "line 14",
  "line 15",
  "line 16",
  "line 17",
  "line 18",
  "line 19",
  "line 20",
  "line 21",
  "line 22",
  "line 23",
  "line 24",
  "line 25",
  "line 26",
  "line 27",
  "line 28",
  "line 29",
  "line 30",
  "line 31",
  "line 32",
  "line 33",
  "line 34",
  "line 35",
  "line 36",
  "line 37",
  "line 38",
  "line 39",
  "line 40",
}

function M.padding()
  return padding
end

-- The last line of the file, so "scrolled all the way down" is unambiguous.
return M

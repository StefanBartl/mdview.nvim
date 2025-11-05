---@module 'mdview.test.diff_harness'
-- Minimal test harness to verify and benchmark a line-diff function.
-- Assumes `compute_line_diff(old, new)` exists and `apply_patch(old, diffs)` exists for verification.

local diff = require("mdview.utils.diff")     -- module providing compute_line_diff
local util = require("mdview.test.apply")    -- module providing apply_patch (see below)
local uv = vim.loop

-- undefined fields on vim.loop; suppress those specific diagnostics for clarity.
---@diagnostic disable: undefined-field, deprecated, undefined-global, unused-local, return-type-mismatch

---@diagnostic disable-next-line
local function assert_eq(a, b, msg)
  if a ~= b then error(msg or "assert_eq failed") end
end

local function make_lines(prefix, n)
  local out = {}
  for i = 1, n do out[i] = prefix .. tostring(i) end
  return out
end

local function run_case(name, old_lines, new_lines)
  local start = uv.now()
  local diffs = diff(old_lines, new_lines)
  local took = uv.now() - start

  -- Apply diffs back to old and verify equality
  local patched = util.apply_patch(old_lines or {}, diffs)
  local ok = true
  if #patched ~= #new_lines then ok = false end
  if ok then
    for i = 1, #new_lines do
      if patched[i] ~= new_lines[i] then ok = false; break end
    end
  end

  -- Compute metrics
  local changed = 0
  for _, d in ipairs(diffs) do changed = changed + (d.count or 0) end
  local total = math.max(1, #new_lines)
  local change_ratio = changed / total

  print(("[test] %s: ok=%s diffs=%d time_ms=%.3f changed=%d ratio=%.3f"):format(
    name, tostring(ok), #diffs, took, changed, change_ratio))

  if not ok then
    error(("Test failed: %s — patched content != new content"):format(name))
  end

  return {
    ok = ok,
    diffs = diffs,
    time_ms = took,
    changed = changed,
    ratio = change_ratio,
  }
end

-- Define test scenarios
local tests = {
  { name = "empty_to_small", old = nil, new = make_lines("L", 10) },
  { name = "no_change", old = make_lines("A", 20), new = make_lines("A", 20) },
  { name = "single_insert_middle", old = (function() local t=make_lines("X",10); table.insert(t,6,"NEW"); return t end)(), new = make_lines("X",11) },
  { name = "single_delete_middle", old = (function() local t=make_lines("X",11); table.remove(t,6); return t end)(), new = make_lines("X",10) },
  { name = "replace_block", old = (function() local t=make_lines("a",50); for i=11,20 do t[i] = "Z"..i end; return t end)(), new = (function() local t=make_lines("a",50); for i=11,20 do t[i] = "Y"..i end; return t end)() },
  { name = "large_append", old = make_lines("P",1000), new = (function() local t=make_lines("P",1000); for i=1001,1500 do t[i] = "P"..i end; return t end)() },
  { name = "many_small_changes", old = make_lines("S",1000), new = (function() local t=make_lines("S",1000); for i=1,1000,50 do t[i] = "Smod"..i end; return t end)() },
}

-- Run tests
local results = {}
for _, tc in ipairs(tests) do
  local r = run_case(tc.name, tc.old, tc.new)
  table.insert(results, r)
end

-- Summarize
local total_time = 0
for _, r in ipairs(results) do total_time = total_time + r.time_ms end
print(("[summary] cases=%d total_time_ms=%.3f"):format(#results, total_time))

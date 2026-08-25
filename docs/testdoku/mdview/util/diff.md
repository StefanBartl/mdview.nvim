# How to evaluate and test the line-diff function

In short: test correctness (functional), robustness (edge cases), performance (large files), and usefulness (how well the patches represent the real change). The sections below provide concrete test cases, metrics, example harnesses in Lua and ways to evaluate automatically.

---

## Table of content

- [1 — What to measure / check](#1--what-to-measure--check)
- [2 — Concrete test cases (unit tests)](#2--concrete-test-cases-unit-tests)
- [3 — A test harness in Lua (busted or plain)](#3--a-test-harness-in-lua-busted-or-plain)
- [4 — Automation / CI](#4--automation--ci)
- [5 — Manual interactive tests (dev workflow)](#5--manual-interactive-tests-dev-workflow)
- [6 — Document the heuristics and thresholds](#6--document-the-heuristics-and-thresholds)
- [7 — Example evaluation table (plain text)](#7--example-evaluation-table-plain-text)
- [8 — Conclusion / checklist (short)](#8--conclusion--checklist-short)

---

## 1 — What to measure / check

- Correctness: does the diff routine produce the expected edit operations for defined (old, new) pairs?
- Idempotence/recovery: `old + diffs` yields `new` after applying the patch (round trip).
- Minimality: are the changes compact (no unnecessarily large replace blocks)?
- Stability: for small changes the diffs stay small (no large shock change).
- Performance: runtime and memory for typical and large files (1k, 10k, 100k lines).
- Heuristic quality: the percentage of changed lines vs. the whole document, thresholds for patch vs. full.

Metrics:

- passes / fails (unit tests)
- avg changed lines per write
- max diff compute time (ms)
- patch size in bytes
- change_ratio = changed_lines / total_lines

---

## 2 — Concrete test cases (unit tests)

Test candidates (all of these should be covered by unit tests):

1. Empty → Full (old=nil, new non-empty) → single replace diff covering whole file.
1. No change → diffs == {}.
1. Single line insertion in middle.
1. Single line deletion in middle.
1. Single line replace.
1. Multiple non-adjacent small edits (prefix/suffix heuristic may merge them; verify behavior).
1. Large append (new lines appended at EOF).
1. Large prepend.
1. Reordering of blocks (detect whether algorithm reports replace for big chunk).
1. Binary or non-utf8 content (ensure lines handling robust).
1. Very large file (10k+ lines) performance measurement.
1. Frequent tiny edits (typing scenario) — stability check.

For every test: apply the diffs to `old` and check whether the result == `new`.

---

## 3 — A test harness in Lua (busted or plain)

The following is a standalone test/benchmark runner in Lua that assumes `compute_line_diff` and checks various scenarios.

```lua
---@module 'mdview.test.diff_harness'
--- Minimal test harness to verify and benchmark a line-diff function.
--- Assumes `compute_line_diff(old, new)` exists and `apply_patch(old, diffs)` exists for verification.
--- English comments only inside code.

local diff = require("mdview.util.diff")     -- module providing compute_line_diff
local util = require("mdview.util.apply")    -- module providing apply_patch (see below)
local uv = vim.loop

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
  local diffs = diff.compute_line_diff(old_lines, new_lines)
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
```

The required helper function `apply_patch` (simple, implementing the prefix/suffix heuristic):

```lua
---@module 'mdview.util.apply'
--- Apply patch objects created by compute_line_diff (prefix/suffix heuristic).
--- English comments inside code.

local M = {}

---@param old_lines string[] previous lines
---@param diffs table[] list of edits returned by compute_line_diff
---@return string[] patched_lines
function M.apply_patch(old_lines, diffs)
  -- If no diffs, return copy of old_lines
  if not diffs or #diffs == 0 then
    local copy = {}
    for i=1, #old_lines do copy[i] = old_lines[i] end
    return copy
  end

  -- start from old_lines copy
  local out = {}
  for i=1, #old_lines do out[i] = old_lines[i] end

  -- For the simple prefix/suffix diff we expect single replace op
  for _, d in ipairs(diffs) do
    if d.op == "replace" then
      local before = vim.list_slice(out, 1, d.start)
      local after = vim.list_slice(out, d.start + (d.count or 0) + 1, #out)
      local merged = {}
      for i=1, #before do table.insert(merged, before[i]) end
      for i=1, #d.lines do table.insert(merged, d.lines[i]) end
      for i=1, #after do table.insert(merged, after[i]) end
      out = merged
    elseif d.op == "insert" then
      local before = vim.list_slice(out, 1, d.start)
      local after = vim.list_slice(out, d.start + 1, #out)
      local merged = {}
      for i=1, #before do table.insert(merged, before[i]) end
      for i=1, #d.lines do table.insert(merged, d.lines[i]) end
      for i=1, #after do table.insert(merged, after[i]) end
      out = merged
    elseif d.op == "delete" then
      local before = vim.list_slice(out, 1, d.start)
      local after = vim.list_slice(out, d.start + (d.count or 0) + 1, #out)
      local merged = {}
      for i=1, #before do table.insert(merged, before[i]) end
      for i=1, #after do table.insert(merged, after[i]) end
      out = merged
    else
      error("unsupported op: "..tostring(d.op))
    end
  end

  return out
end

return M
```

---

## 4 — Automation / CI

- Add the tests as a `lua` test script and run it in CI (GitHub Actions).
- Collect metrics per test run (time, ratio) and fail PRs when e.g. `time_ms` > threshold or `ratio` > 0.6 for small edits.
- Option: fuzz testing — generate random edits (insert/delete/replace) and check the round-trip invariants.

---

## 5 — Manual interactive tests (dev workflow)

- Open a large markdown file (1k+ lines) in Neovim.
- Change individual lines (simulating typing) and measure: the time to compute the diff (instrument with `uv.now()` around the computation), the bytes sent (payload size).
- Change large blocks (copy/paste) and check whether the heuristic sends the full content instead of a patch.
- Simulate a lost patch: drop the first patch on the server and check the recovery (the server requests a full resend or the client falls back).

---

## 6 — Document the heuristics and thresholds

Proposal (note it in the README):

- If changed_lines / total_lines > 0.5 → send full content.
- If number_of_diffs > 5 → send full content.
- If computing diff takes > 10 ms for small files (\<1k lines) → consider faster heuristic.
- Retry/backoff: 150ms base, 2^n backoff, max 5 tries.

---

## 7 — Example evaluation table (plain text)

| Test case            | diffs | changed lines | time ms | change_ratio |
| -------------------- | ----: | ------------: | ------: | -----------: |
| empty_to_small       |     1 |            10 |    0.12 |         1.00 |
| no_change            |     0 |             0 |    0.01 |         0.00 |
| single_insert_middle |     1 |             1 |    0.02 |         0.01 |
| large_append         |     1 |           500 |     1.3 |         0.33 |

---

## 8 — Conclusion / checklist (short)

- Implement `apply_patch` and unit tests (round trip).
- Test the edge cases (empty, huge files, many small edits).
- Collect metrics (time, ratio, patch size) and define thresholds.
- Optional: fuzz tests and CI gating.

---

# Wie man die Line-Diff-Funktion bewertet und testet

## Table of content

  - [1 — Was man messen / prüfen sollte](#1-was-man-messen-prfen-sollte)
  - [2 — Konkrete Testfälle (Unit Tests)](#2-konkrete-testflle-unit-tests)
  - [3 — Test-Harness in Lua (busted oder plain)](#3-test-harness-in-lua-busted-oder-plain)
  - [4 — Automatisierung / CI](#4-automatisierung-ci)
  - [5 — Manuelle interaktive Tests (Dev workflow)](#5-manuelle-interaktive-tests-dev-workflow)
  - [6 — Heuristiken und Schwellenwerte dokumentieren](#6-heuristiken-und-schwellenwerte-dokumentieren)
  - [7 — Beispiel-Auswertungstabelle (Klartext)](#7-beispiel-auswertungstabelle-klartext)
  - [8 — Fazit / Checklist (Kurz)](#8-fazit-checklist-kurz)

---

Kurz: testet Korrektheit (funktional), Robustheit (Edge-Cases), Performanz (große Dateien), und Nutzwert (wie gut Patches die reale Änderung abbilden). Die folgenden Abschnitte liefern konkrete Testfälle, Metriken, Beispiel-Harnesses in Lua und Wege zur automatischen Bewertung.

---

## 1 — Was man messen / prüfen sollte

* Korrektheit: erzeugt die Diff-Routine erwartete Edit-Operationen für definierte Paare (old, new)?
* Idempotenz/Recovery: aus `old + diffs` ergibt sich `new` nach Patch-Anwendung (round-trip).
* Minimalität: sind die Änderungen kompakt (nicht unnötig große Replace-Blöcke)?
* Stabilität: bei kleinen Änderungen bleiben Diffs klein (keine große Schock-Änderung).
* Performanz: Laufzeit und Speicher für typische und große Dateien (1k, 10k, 100k Zeilen).
* Heuristische Güte: Prozent geänderter Zeilen vs. Gesamtdokument, Schwellwerte für Patch-vs-Full.

Metriken:

* passes / fails (unit tests)
* avg changed lines per write
* max diff compute time (ms)
* patch size in bytes
* change_ratio = changed_lines / total_lines

---

## 2 — Konkrete Testfälle (Unit Tests)

Testkandidaten (sollte alle in Unit-Tests abgedeckt sein):

1. Empty → Full (old=nil, new non-empty) → single replace diff covering whole file.
2. No change → diffs == {}.
3. Single line insertion in middle.
4. Single line deletion in middle.
5. Single line replace.
6. Multiple non-adjacent small edits (prefix/suffix heuristic may merge them; verify behavior).
7. Large append (new lines appended at EOF).
8. Large prepend.
9. Reordering of blocks (detect whether algorithm reports replace for big chunk).
10. Binary or non-utf8 content (ensure lines handling robust).
11. Very large file (10k+ lines) performance measurement.
12. Frequent tiny edits (typing scenario) — stability check.

Für jede Test gilt: wende diffs auf `old` an und überprüfe, ob result == `new`.

---

## 3 — Test-Harness in Lua (busted oder plain)

Folgendes ist ein eigenständiger Test-/benchmark-runner in Lua, der die `compute_line_diff` annimmt und verschiedene Szenarien prüft.

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

Erforderliche Hilfsfunktion `apply_patch` (einfach, implementiert die prefix/suffix heuristic):

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

## 4 — Automatisierung / CI

* Füge die Tests als `lua` Testscript hinzu und führen es in CI (GitHub Actions) aus.
* Sammle Metriken per Testlauf (Zeit, ratio) und fail die PRs, wenn z. B. `time_ms` > threshold oder `ratio` > 0.6 für small edits.
* Option: fuzz-testing: generiere random edits (insert/delete/replace) und prüfe round-trip invariants.

---

## 5 — Manuelle interaktive Tests (Dev workflow)

* Öffne große Markdown (1k+ Zeilen) in Neovim.
* Ändere einzelne Zeilen (simulate typing) und messe: time to compute diff (instrumentiere mit `uv.now()` around compute), bytes sent (size of payload).
* Ändere große Blöcke (copy/paste) und prüfe, ob heuristic send full instead of patch.
* Simuliere lost-patch: drop first patch on server and check recovery (server requests full resend or client falls back).

---

## 6 — Heuristiken und Schwellenwerte dokumentieren

Vorschlag (notiere im README):

* If changed_lines / total_lines > 0.5 → send full content.
* If number_of_diffs > 5 → send full content.
* If computing diff takes > 10 ms for small files (<1k lines) → consider faster heuristic.
* Retry/backoff: 150ms base, 2^n backoff, max 5 tries.

---

## 7 — Beispiel-Auswertungstabelle (Klartext)

| Test case            | diffs | changed lines | time ms | change_ratio |
| -------------------- | ----: | ------------: | ------: | -----------: |
| empty_to_small       |     1 |            10 |    0.12 |         1.00 |
| no_change            |     0 |             0 |    0.01 |         0.00 |
| single_insert_middle |     1 |             1 |    0.02 |         0.01 |
| large_append         |     1 |           500 |     1.3 |         0.33 |

---

## 8 — Fazit / Checklist (Kurz)

* Implementiere `apply_patch` und Unit-Tests (round-trip).
* Teste Edge-Cases (empty, huge files, many small edits).
* Sammle metriken (time, ratio, patch size) und definiere thresholds.
* Optional: fuzz tests und CI-gating.

---

# Test harness for the line-diff function in mdview.nvim

This short markdown document describes how to run `diff_harness.lua` in order to test the line-diff function (`mdview.util.diff`) and verify the results.

---

## Table of content

- [1. Prerequisites](#1-prerequisites)
- [2. Goal](#2-goal)
- [3. Test scenarios](#3-test-scenarios)
- [4. Running it](#4-running-it)
- [5. Analysing the results](#5-analysing-the-results)
- [6. Notes](#6-notes)
- [7. Debugging](#7-debugging)
- [8. Summary](#8-summary)
- [Literature](#literature)

---

## 1. Prerequisites

- Neovim 0.9+ (for `vim.loop` / luv)

- Lua 5.1+ (LuaJIT)

- The `mdview.nvim` repository checked out and runnable

- The modules:
  - `mdview.util.diff` (the line-diff function)
  - `mdview.util.apply` (the helper `apply_patch` for testing the patches)

---

## 2. Goal

- Verify that the line-diff function delivers correct patch information.
- Benchmark the runtime for various scenarios.
- Test consistency by applying the patches to the original content and comparing the result with the new content.

---

## 3. Test scenarios

Several scenarios are predefined in the harness:

| Scenario               | Description                                       |
| ---------------------- | ------------------------------------------------- |
| `empty_to_small`       | An empty file → a small file (10 lines)           |
| `no_change`            | No change between `old` and `new`                 |
| `single_insert_middle` | One line is inserted in the middle                |
| `single_delete_middle` | One line is deleted in the middle                 |
| `replace_block`        | A block of lines is replaced                      |
| `large_append`         | Appending many lines at the end                   |
| `many_small_changes`   | Many small changes spread over 1000 lines         |

---

## 4. Running it

1. Open Neovim in the root directory of `mdview.nvim`.
1. Load the file `diff_harness.lua` via `:luafile`:

```vim
:luafile lua/mdview/test/diff_harness.lua
```

3. Alternatively, start it directly from Lua:

```bash
nvim --headless -c "luafile lua/mdview/test/diff_harness.lua" -c "qa"
```

4. The console shows, for every scenario:

```
[test] <scenario>: ok=true diffs=<count> time_ms=<milliseconds> changed=<lines> ratio=<ratio>
```

5. And a summary at the end:

```
[summary] cases=<count> total_time_ms=<milliseconds>
```

---

## 5. Analysing the results

- `ok=true`: the patch transformed `old_lines` into `new_lines` correctly.
- `diffs=<count>`: the number of patch operations.
- `time_ms`: the computation time in milliseconds.
- `changed`: the number of changed lines.
- `ratio`: the ratio of changed lines to total lines (0–1).

---

## 6. Notes

- On failure, Lua errors are printed with details about the failed operation.
- To improve the diff function, alternative algorithms such as LCS (Myers) can be used.
- The function `apply_patch` has to be implemented correctly in order to apply the patches to `old_lines`.

---

## 7. Debugging

- Enable detailed logging in `diff.lua`:

```lua
print(vim.inspect(diffs))
```

- Check that `patched` matches the new content exactly:

```lua
for i, line in ipairs(new_lines) do
  assert(line == patched[i], "Line mismatch at "..i)
end
```

---

## 8. Summary

With `diff_harness.lua` you can:

- check the functionality and correctness of the line-diff function.
- measure performance and derive optimisations.
- detect regressions when the diff logic changes.

---

## Literature

- Lua `vim.loop` / luv documentation
- EmmyLua type annotations for tables and arrays
- The Myers diff algorithm as a reference implementation

---

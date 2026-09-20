---@module 'tests.nvim.probe_platform_paths_spec'
-- Pins two bugs found and fixed in mdview.adapter.browser.probe_platform_paths
-- (see TESTS/README.md's 2026-09-20 entry): an ipairs()-over-a-table-literal
-- nil hole that silently dropped Windows candidates, and a Linux Edge probe
-- path using the Windows-only "msedge" name instead of the real
-- "microsoft-edge" binary. Follows this suite's existing convention (see
-- server_args_spec.lua) of testing against whichever OS actually runs the
-- suite rather than mocking vim.fn.has.

---@diagnostic disable: undefined-global

local probe = require("mdview.adapter.browser.probe_platform_paths")

local windows = vim.fn.has("win32") == 1
local mac = vim.fn.has("mac") == 1
local linux = not windows and not mac

describe("probe_platform_paths", function()
  if windows then
    it("still probes LOCALAPPDATA-based paths when PROGRAMFILES(X86) is unset", function()
      local orig_getenv = os.getenv
      local local_appdata = orig_getenv("LOCALAPPDATA")
      -- luacheck: push ignore 122
      os.getenv = function(name)
        if name == "PROGRAMFILES(X86)" then
          return nil
        end
        return orig_getenv(name)
      end
      local ok, paths = pcall(probe)
      os.getenv = orig_getenv
      -- luacheck: pop
      assert(ok, paths)

      if local_appdata then
        local found = false
        for _, p in ipairs(paths) do
          if p:find(local_appdata, 1, true) then
            found = true
          end
        end
        assert.is_true(found, "expected a LOCALAPPDATA-based candidate even without PROGRAMFILES(X86)")
      end
    end)
  end

  if linux then
    it("probes the real microsoft-edge binary name, not the Windows-only 'msedge'", function()
      local paths = probe()
      local has_edge, has_wrong_name = false, false
      for _, p in ipairs(paths) do
        if p:find("microsoft-edge", 1, true) then
          has_edge = true
        end
        if p:find("/msedge", 1, true) then
          has_wrong_name = true
        end
      end
      assert.is_true(has_edge, "expected a microsoft-edge candidate on Linux")
      assert.is_false(has_wrong_name, "msedge is not a real Linux binary name")
    end)
  end
end)

---@module 'tests.nvim.health_spec'
-- Verifies mdview.health.check() -- the :checkhealth report generator --
-- actually runs to completion instead of crashing partway through.
--
-- Round 25 excluded this file entirely as "declarative :checkhealth ...
-- generator[s]" with no branching logic of its own. That reasoning didn't
-- hold: M.check() has real branches (lib.nvim present/missing, curl/tar
-- present/missing, a running vs. idle session, an installed vs. uninstalled
-- cache) AND a real bug -- see the BUG case below -- so it gets a real spec
-- like everything else that runs through the shared vim.health API.
--
-- Deliberately not asserted here: the exact ok()/warn()/error() message text
-- (vim.health writes straight into the global health report machinery, not
-- a return value this spec can capture) and the "curl subprocess actually
-- reachable" branch's precise output -- both would either duplicate what the
-- function already documents about itself in comments, or require a real
-- curl call. What IS asserted, matching the existing "delegates ... without
-- erroring" pattern already used in usrcmds_session_actions_spec.lua, is
-- that M.check() completes without throwing across its real branches.

---@diagnostic disable: undefined-global

local health = require("mdview.health")
local state = require("mdview.core.state")

describe("health.check", function()
  it("completes without erroring under normal (idle-session) conditions", function()
    local ok, err = pcall(health.check)
    assert.is_true(ok, "health.check() must not throw -- got: " .. tostring(err))
  end)

  it("completes without erroring when a session looks like it's running", function()
    -- Force M.proc_is_running() true without a real spawned process, and
    -- stub vim.fn.system (a Neovim global, not a require() upvalue -- no
    -- package.loaded gymnastics needed) so the /health probe this branch
    -- takes can't shell out to a real curl subprocess.
    local prev_proc = state.get_proc()
    state.set_proc({ handle = {
      is_closing = function()
        return false
      end,
    } })
    local orig_system = vim.fn.system
    vim.fn.system = function()
      return "ok"
    end

    local ok, err = pcall(health.check)

    vim.fn.system = orig_system
    state.set_proc(prev_proc)

    assert.is_true(ok, "health.check() must not throw with a (faked) running session -- got: " .. tostring(err))
  end)

  it("BUG (fixed): does not crash when lib.nvim.bindings.usercmd.composer fails to load", function()
    -- health.lua used to end with an unguarded
    -- `require("lib.nvim.bindings.usercmd.composer").checkhealth(...)`,
    -- crashing :checkhealth outright on any lib.nvim too old/partial to
    -- have that submodule -- discarding every ok/warn/error already
    -- reported earlier in the SAME call, including the graceful
    -- "lib.nvim not found" report this function goes out of its way to
    -- produce. Simulated here via package.preload, the standard way to
    -- make a `require()` fail for a module that (unlike most seams in this
    -- suite) is not itself an upvalue mdview captured at load time --
    -- health.lua requires it fresh on every M.check() call.
    local mod_name = "lib.nvim.bindings.usercmd.composer"
    local cached = package.loaded[mod_name]
    package.loaded[mod_name] = nil
    package.preload[mod_name] = function()
      error("simulated: composer unavailable (old/incompatible lib.nvim)")
    end

    local ok, err = pcall(health.check)

    package.preload[mod_name] = nil
    package.loaded[mod_name] = cached

    assert.is_true(
      ok,
      "health.check() must degrade gracefully, not crash, when this lib.nvim submodule is unavailable -- got: "
        .. tostring(err)
    )
  end)

  it("lists the tabs of other display languages with their state", function()
    local rooms = require("mdview.core.lang_rooms")
    local config = require("mdview.config")
    local prev_key, prev_behavior = state.get_preview_key(), config.defaults.browser.behavior
    state.set_preview_key("health-spec-room")
    config.defaults.browser.behavior = "reuse"
    local said = {}
    local real_ok, real_warn = vim.health.ok, vim.health.warn
    vim.health.ok = function(msg)
      said[#said + 1] = msg
    end
    vim.health.warn = function(msg)
      said[#said + 1] = msg
    end
    -- health.lua binds vim.health.ok / warn when it loads: load it again with the stubs in place.
    package.loaded["mdview.health"] = nil
    local fresh = require("mdview.health")
    pcall(fresh.check)
    local none = table.concat(said, " | ")
    rooms.add("es")
    said = {}
    pcall(fresh.check)
    local with = table.concat(said, " | ")
    vim.health.ok, vim.health.warn = real_ok, real_warn
    package.loaded["mdview.health"] = health
    rooms.reset()
    state.set_preview_key(prev_key)
    config.defaults.browser.behavior = prev_behavior
    assert.is_truthy(none:find("no tab of another display language", 1, true))
    assert.is_truthy(with:find('tab "es"', 1, true), "the report names the tab")
  end)
end)

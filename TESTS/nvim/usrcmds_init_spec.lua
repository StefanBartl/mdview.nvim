---@module 'tests.nvim.usrcmds_init_spec'
-- mdview.bindings.usrcmds (the :MDView command-tree registration itself) was
-- entirely unexercised: no existing spec calls M.attach() (the harness
-- deliberately never calls require("mdview").setup(), which is the only
-- normal path to it -- see harness.lua's own comment), so the giant route
-- table and the one real piece of logic in this file, log_level_routes()'s
-- generate-then-sort, had zero coverage.
--
-- The individual route handlers (start.run, stop.run, theme.run, ...) are
-- already covered directly in their own specs -- this file only tests what
-- is genuinely this module's own: that log_level_routes() stays in sync with
-- log.LEVELS and sorted, and that M.attach() (composer.verb registration,
-- not a Neovim-side-effect-free call) completes without erroring.

---@diagnostic disable: undefined-global

local usrcmds = require("mdview.bindings.usrcmds")
local log = require("mdview.bindings.usrcmds.log")

describe("usrcmds._log_level_routes", function()
  it("produces exactly one route per known log level", function()
    local routes = usrcmds._log_level_routes()
    local count = 0
    for _ in pairs(log.LEVELS) do
      count = count + 1
    end
    assert.are.equal(count, #routes)
  end)

  it("every route path is {'log', <level name>} and desc mentions the level", function()
    local routes = usrcmds._log_level_routes()
    for _, r in ipairs(routes) do
      assert.are.equal("log", r.path[1])
      assert(log.LEVELS[r.path[2]] ~= nil, "unknown level in route path: " .. tostring(r.path[2]))
      assert(r.desc:find(r.path[2]:upper(), 1, true), "desc should mention the level name")
    end
  end)

  it("is sorted alphabetically by level name (stable Tab-completion order)", function()
    local routes = usrcmds._log_level_routes()
    for i = 2, #routes do
      assert(routes[i - 1].path[2] < routes[i].path[2], "routes must be sorted by level name")
    end
  end)
end)

describe("usrcmds.attach", function()
  it("registers the :MDView command tree without erroring", function()
    local ok, err = pcall(usrcmds.attach)
    assert.is_true(ok, "usrcmds.attach() must not throw -- got: " .. tostring(err))
    -- exists(':cmd') returns 2 for an exact command-name match, 1 only for a
    -- prefix match -- see :h exists().
    assert.are.equal(2, vim.fn.exists(":MDView"))
  end)

  it("is idempotent: attaching twice does not error (re-registration, not duplication)", function()
    local ok1 = pcall(usrcmds.attach)
    local ok2 = pcall(usrcmds.attach)
    assert.is_true(ok1)
    assert.is_true(ok2)
  end)
end)

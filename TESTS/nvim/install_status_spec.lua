---@module 'tests.nvim.install_status_spec'
-- Verifies mdview.adapter.install.status(): a read-only report of whether the
-- platform binary / client bundle for the CURRENTLY CONFIGURED install
-- version are already cached, used by :checkhealth and :MDView diagnose. No
-- network, no download -- just filesystem checks against whatever
-- install.version happens to resolve to.
--
-- A disposable, never-real version string is used so this test's own
-- mkdir/touch calls can't collide with (or be mistaken for) an actual
-- cached install on the machine running the suite, and so nothing has to be
-- cleaned up from the real stdpath("data")/mdview/bin/<real version> tree.

---@diagnostic disable: undefined-global

local install = require("mdview.adapter.install")
local config = require("mdview.config")

local orig_version = config.defaults.install.version
local TEST_VERSION = "v0.0.0-mdview-spec-" .. tostring(vim.uv.hrtime())
config.defaults.install.version = TEST_VERSION

describe("install.status", function()
  local status0 = install.status()

  it("reports nothing installed for a version nothing has touched yet", function()
    assert.is_false(status0.binary_installed)
    assert.is_false(status0.client_installed)
    assert(status0.binary_path:find(TEST_VERSION, 1, true), "binary_path should be scoped to this test version")
    assert(status0.client_dir:find(TEST_VERSION, 1, true), "client_dir should be scoped to this test version")
  end)

  it("flips binary_installed once a file exists at the exact resolved path", function()
    vim.fn.mkdir(vim.fn.fnamemodify(status0.binary_path, ":h"), "p")
    local f = io.open(status0.binary_path, "w")
    f:write("")
    f:close()

    local status1 = install.status()
    assert.is_true(status1.binary_installed)
    assert.are.equal(status0.binary_path, status1.binary_path)
    assert.is_false(status1.client_installed) -- unaffected
  end)

  it("flips client_installed once the client_dir exists (directory presence only)", function()
    vim.fn.mkdir(status0.client_dir, "p")
    local status2 = install.status()
    assert.is_true(status2.client_installed)
    assert.are.equal(status0.client_dir, status2.client_dir)
  end)

  -- Clean up the disposable test-version tree.
  vim.fn.delete(vim.fn.fnamemodify(status0.binary_path, ":h"), "rf")
end)

config.defaults.install.version = orig_version

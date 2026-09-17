---@module 'tests.nvim.launcher_url_spec'
-- Verifies launcher.resolve_browser_url: the single place every query
-- parameter the client reads (?theme=, ?hl=, ?cursor=, ?zoom=, ?sel=, ...) is
-- assembled for the opened preview tab. Never exercised before -- every other
-- spec that touches the launcher only reaches it transitively. Also covers
-- M.has_display, the display-detection gate for browser autostart.

---@diagnostic disable: undefined-global

local launcher = require("mdview.bindings.usrcmds.start.server.launcher")
local state = require("mdview.core.state")
local config = require("mdview.config")
local bcfg = require("mdview.config.browser")

--- Snapshot everything resolve_browser_url reads, run `fn`, then restore it
--- exactly -- this function reads from half a dozen shared config tables plus
--- vim.g and state.
---@param fn fun()
local function with_clean_state(fn)
  local token0 = state.get_token()
  local browser0 = vim.deepcopy(bcfg.defaults)
  local exp0 = vim.deepcopy(config.defaults.experimental)
  local sync_cb0, sync_f0 = config.defaults.sync_checkboxes, config.defaults.sync_fields
  local g_dev0, g_srv0, g_wt0 = vim.g.mdview_dev_port, vim.g.mdview_server_port, vim.g.mdview_wt_cert_hash

  local ok, err = pcall(fn)

  state.set_token(token0)
  for k, v in pairs(browser0) do
    bcfg.defaults[k] = v
  end
  for k, v in pairs(exp0) do
    config.defaults.experimental[k] = v
  end
  config.defaults.sync_checkboxes = sync_cb0
  config.defaults.sync_fields = sync_f0
  vim.g.mdview_dev_port = g_dev0
  vim.g.mdview_server_port = g_srv0
  vim.g.mdview_wt_cert_hash = g_wt0

  if not ok then
    error(err, 0)
  end
end

--- Parse a URL's query string into a plain table (last value wins, which
--- never matters here since resolve_browser_url never repeats a param).
---@param url string
---@return table<string, string>
local function query_of(url)
  local q = url:match("%?(.*)$") or ""
  local out = {}
  for pair in q:gmatch("[^&]+") do
    local k, v = pair:match("^([^=]+)=(.*)$")
    if k then
      out[k] = v
    end
  end
  return out
end

describe("launcher.resolve_browser_url", function()
  it("an explicit opts.browser_url wins over everything else", function()
    with_clean_state(function()
      bcfg.defaults.open_url = "http://example.invalid/static"
      local url = launcher.resolve_browser_url({ browser_url = "http://explicit.invalid/", key = "x" })
      assert.are.equal("http://explicit.invalid/", url)
    end)
  end)

  it("a static browser.open_url wins over the computed base", function()
    with_clean_state(function()
      bcfg.defaults.open_url = "http://static.invalid/"
      local url = launcher.resolve_browser_url({ key = "x" })
      assert.are.equal("http://static.invalid/", url)
    end)
  end)

  it("returns just the base URL when there is no key or no token", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      vim.g.mdview_server_port = 43219
      state.set_token(nil)
      local url = launcher.resolve_browser_url({ key = "some/doc.md" })
      assert.are.equal("http://localhost:43219/", url)
    end)
  end)

  it("prefers the detected Vite dev port over the backend server port", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      vim.g.mdview_dev_port = 43220
      vim.g.mdview_server_port = 43219
      state.set_token(nil)
      local url = launcher.resolve_browser_url({})
      assert.are.equal("http://localhost:43220/", url)
    end)
  end)

  it("builds key + token once both are present", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      vim.g.mdview_server_port = 43219
      vim.g.mdview_dev_port = nil
      state.set_token("tok123")
      local url = launcher.resolve_browser_url({ key = "C:/docs/notes.md" })
      local q = query_of(url)
      assert.are.equal("tok123", q.token)
      assert(q.key, "expected a key= param")
      assert.is_nil(q.key:find("C:", 1, true)) -- normalize.path_for_url strips the bare "C:"
    end)
  end)

  it("carries theme/highlighter/extlinks/cursor even at their defaults (always non-empty strings)", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      state.set_token("t")
      local url = launcher.resolve_browser_url({ key = "k" })
      local q = query_of(url)
      assert.are.equal("github", q.theme)
      assert.are.equal("hljs", q.hl)
      assert.are.equal("new_tab", q.extlinks)
      assert.are.equal("line", q.cursor)
    end)
  end)

  it("click_navigate is ON by default and adds nav=1", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      state.set_token("t")
      local q = query_of(launcher.resolve_browser_url({ key = "k" }))
      assert.are.equal("1", q.nav)
    end)
  end)

  it("omits nav= once click_navigate is switched off", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      state.set_token("t")
      config.defaults.experimental.click_navigate = false
      local q = query_of(launcher.resolve_browser_url({ key = "k" }))
      assert.is_nil(q.nav)
    end)
  end)

  it("reverse_scroll adds rscroll=1 only when on", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      state.set_token("t")
      config.defaults.experimental.reverse_scroll = true
      local q = query_of(launcher.resolve_browser_url({ key = "k" }))
      assert.are.equal("1", q.rscroll)
    end)
  end)

  it("zoom is omitted at the default (1.0) and included otherwise", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      state.set_token("t")
      bcfg.defaults.zoom = 1.0
      assert.is_nil(query_of(launcher.resolve_browser_url({ key = "k" })).zoom)

      bcfg.defaults.zoom = 1.5
      assert.are.equal("1.500", query_of(launcher.resolve_browser_url({ key = "k" })).zoom)
    end)
  end)

  it("selection_sync adds sel=1 only when on", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      state.set_token("t")
      bcfg.defaults.selection_sync = false
      assert.is_nil(query_of(launcher.resolve_browser_url({ key = "k" })).sel)

      bcfg.defaults.selection_sync = true
      assert.are.equal("1", query_of(launcher.resolve_browser_url({ key = "k" })).sel)
    end)
  end)

  it("preserve_blank_lines adds blanklines=1 only when on", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      state.set_token("t")
      bcfg.defaults.preserve_blank_lines = true
      assert.are.equal("1", query_of(launcher.resolve_browser_url({ key = "k" })).blanklines)
    end)
  end)

  it("webtransport adds transport= and, if present, the printed cert hash", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      state.set_token("t")
      config.defaults.experimental.webtransport = true
      vim.g.mdview_wt_cert_hash = "deadbeef"
      local q = query_of(launcher.resolve_browser_url({ key = "k" }))
      assert.are.equal("webtransport", q.transport)
      assert.are.equal("deadbeef", q.wtcerthash)
    end)
  end)

  it("sync_checkboxes/sync_fields only appear (as 0) when explicitly disabled", function()
    with_clean_state(function()
      bcfg.defaults.open_url = nil
      state.set_token("t")
      config.defaults.sync_checkboxes = true
      config.defaults.sync_fields = true
      assert.is_nil(query_of(launcher.resolve_browser_url({ key = "k" })).sync)

      config.defaults.sync_checkboxes = false
      config.defaults.sync_fields = false
      local q = query_of(launcher.resolve_browser_url({ key = "k" }))
      assert.are.equal("0", q.sync)
      assert.are.equal("0", q.fields)
    end)
  end)
end)

describe("launcher.has_display", function()
  it("is always true on Windows/macOS", function()
    if vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1 then
      assert.is_true(launcher.has_display())
    end
  end)

  it("on other Unix, follows DISPLAY/WAYLAND_DISPLAY", function()
    if vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1 then
      return
    end
    local d0, w0 = vim.env.DISPLAY, vim.env.WAYLAND_DISPLAY
    vim.env.DISPLAY = nil
    vim.env.WAYLAND_DISPLAY = nil
    assert.is_false(launcher.has_display())
    vim.env.DISPLAY = ":0"
    assert.is_true(launcher.has_display())
    vim.env.DISPLAY = d0
    vim.env.WAYLAND_DISPLAY = w0
  end)
end)

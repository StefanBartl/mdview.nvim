---@module 'tests.nvim.mirror_guard_spec'
-- Guard against regression: the buffer text for the preview must come from
-- mdview.core.mirror. Any other `nvim_buf_get_lines` under lua/mdview is a
-- stray read that a future transform (display language) would miss. The
-- documented exceptions are listed in the header of core/mirror.lua.

---@diagnostic disable: undefined-global

local ALLOWED = {
  ["core/mirror.lua"] = true,
  ["adapter/inbound_poll.lua"] = true,
  ["core/breadcrumbs.lua"] = true,
  ["test/runner.lua"] = true,
}

---@return string root
local function lua_root()
  local src = debug.getinfo(1, "S").source:sub(2)
  local plugin = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(src)))
  return plugin .. "/lua/mdview"
end

describe("mdview.core.mirror guard", function()
  it("keeps nvim_buf_get_lines out of lua/mdview except the documented exceptions", function()
    local root = lua_root()
    local offenders = {}
    for name, kind in vim.fs.dir(root, { depth = 10 }) do
      if kind == "file" and name:match("%.lua$") and not ALLOWED[name] then
        local f = io.open(root .. "/" .. name, "r")
        if f then
          local n = 0
          for line in f:lines() do
            n = n + 1
            -- Comments may mention the function name.
            if not line:match("^%s*%-%-") and line:find("nvim_buf_get_lines", 1, true) then
              offenders[#offenders + 1] = name .. ":" .. n
            end
          end
          f:close()
        end
      end
    end
    assert.are.same({}, offenders)
  end)

  it("mirror.lines returns the buffer text as a fresh table", function()
    local mirror = require("mdview.core.mirror")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b" })
    local got = mirror.lines(buf)
    assert.are.same({ "a", "b" }, got)
    got[1] = "x"
    assert.are.same({ "a", "b" }, mirror.lines(buf))
    local seen
    mirror.lines_async(buf, function(l)
      seen = l
    end)
    assert.are.same({ "a", "b" }, seen)
  end)
end)

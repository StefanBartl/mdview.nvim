---@module 'tests.nvim.mirror_guard_spec'
-- Guard against regression: the text for the preview, from a buffer or from a
-- file, must come from mdview.core.mirror. Any raw read route under lua/mdview
-- (the buffer API, the file API, the Vimscript and luv equivalents of both) is a
-- stray read that a future transform (display language) would miss.
--
-- An exception is granted per ROUTE, not per file: a file that may read the real
-- buffer is not thereby allowed to read a file from disk. The exceptions are
-- documented in the header of core/mirror.lua; RULES below is their data, and an
-- exception that no longer has a use is itself a failure (so the table cannot
-- grow wider than the code needs).

---@diagnostic disable: undefined-global

local MIRROR = "core/mirror.lua"

--- A source line uses the identifier `name`, as a whole word: `getline` is not
--- found in `getlines`, `fs_read` not in `fs_readdir`. A dot in `name` is a dot.
---@param name string
---@return fun(line: string): boolean
local function word(name)
  local pattern = "%f[%w_]" .. name:gsub("%p", "%%%0") .. "%f[^%w_]"
  return function(line)
    return line:find(pattern) ~= nil
  end
end

--- A source line opens a file with `io.open` in a mode that can read: a mode
--- literal that does not start with `w` or `a`, a mode that is not a literal, no
--- mode at all, or a call whose closing parenthesis is on a later line (the mode
--- is not visible, so it is not assumed to be a write).
---@param line string
---@return boolean
local function io_open_reads(line)
  local call = line:match("%f[%w_]io%.open%s*(%b())")
  if not call then
    return line:find("%f[%w_]io%.open%s*%(") ~= nil
  end
  local mode = call:match(",%s*[\"']([^\"']*)[\"']%s*%)$")
  return not (mode and mode:match("^[wa]") ~= nil)
end

---@class MirrorGuardRule
---@field route string # named in a finding
---@field hit fun(line: string): boolean # the source line uses the route
---@field allowed string[] # the files (path under lua/mdview) that may use it

---@type MirrorGuardRule[]
local RULES = {
  -- The buffer side. The three exceptions read the REAL buffer, not the preview.
  {
    route = "nvim_buf_get_lines",
    hit = word("nvim_buf_get_lines"),
    allowed = { MIRROR, "adapter/inbound_poll.lua", "core/breadcrumbs.lua", "test/runner.lua" },
  },
  { route = "nvim_buf_get_text", hit = word("nvim_buf_get_text"), allowed = {} },
  { route = "getbufline", hit = word("getbufline"), allowed = {} },
  { route = "getbufoneline", hit = word("getbufoneline"), allowed = {} },
  { route = "getline", hit = word("getline"), allowed = {} },
  { route = "get_node_text", hit = word("get_node_text"), allowed = {} },
  -- The disk side: a file that is not open in a buffer is read by mirror.lines_for_path.
  { route = "readfile", hit = word("readfile"), allowed = { MIRROR } },
  { route = "readblob", hit = word("readblob"), allowed = {} },
  { route = "fs_read", hit = word("fs_read"), allowed = {} },
  { route = "io.lines", hit = word("io.lines"), allowed = {} },
  -- Only the read modes: the log, a temp file or a report is written with io.open too.
  { route = "io.open (read mode)", hit = io_open_reads, allowed = { "adapter/install.lua" } },
}

--- The routes a source file uses that it may not.
---@param name string # path of the file under lua/mdview
---@param lines string[]
---@return string[] offenders # "name:line (route)"
---@return table<string, boolean> used # route -> the file uses it at least once
local function scan(name, lines)
  local offenders, used = {}, {}
  for n, line in ipairs(lines) do
    -- Comments may mention the function names.
    if not line:match("^%s*%-%-") then
      for _, rule in ipairs(RULES) do
        if rule.hit(line) then
          used[rule.route] = true
          if not vim.tbl_contains(rule.allowed, name) then
            offenders[#offenders + 1] = name .. ":" .. n .. " (" .. rule.route .. ")"
          end
        end
      end
    end
  end
  return offenders, used
end

---@return string root
local function lua_root()
  local src = debug.getinfo(1, "S").source:sub(2)
  local plugin = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(src)))
  return plugin .. "/lua/mdview"
end

--- Scans every Lua file under lua/mdview.
---@return string[] offenders
---@return table<string, table<string, boolean>> used # file -> route -> true
local function scan_tree()
  local root = lua_root()
  local all_offenders, all_used = {}, {}
  for name, kind in vim.fs.dir(root, { depth = 10 }) do
    if kind == "file" and name:match("%.lua$") then
      local f = io.open(root .. "/" .. name, "r")
      if f then
        local lines = {}
        for line in f:lines() do
          lines[#lines + 1] = line
        end
        f:close()
        local offenders, used = scan(name, lines)
        vim.list_extend(all_offenders, offenders)
        all_used[name] = used
      end
    end
  end
  return all_offenders, all_used
end

describe("mdview.core.mirror guard", function()
  it("keeps raw buffer/disk reads out of lua/mdview except the documented exceptions", function()
    local offenders = scan_tree()
    assert.are.same({}, offenders)
  end)

  it("has no exception that is no longer used (the table is not wider than the code)", function()
    local _, used = scan_tree()
    -- A vacuous scan (a wrong root, an unreadable tree) would pass the test above.
    assert.is_truthy(used[MIRROR], "core/mirror.lua was not scanned")
    local stale = {}
    for _, rule in ipairs(RULES) do
      for _, file in ipairs(rule.allowed) do
        if not (used[file] and used[file][rule.route]) then
          stale[#stale + 1] = file .. " (" .. rule.route .. ")"
        end
      end
    end
    assert.are.same({}, stale)
  end)

  describe("scan (the guard itself)", function()
    ---@param name string
    ---@param line string
    ---@return string[]
    local function offenders_of(name, line)
      return (scan(name, { line }))
    end

    it("grants an exception per route: the file that may read the buffer may not read from disk", function()
      assert.are.same({}, offenders_of("adapter/inbound_poll.lua", "local l = api.nvim_buf_get_lines(b, 0, -1, false)"))
      assert.are.same(
        { "adapter/inbound_poll.lua:1 (readfile)" },
        offenders_of("adapter/inbound_poll.lua", "local l = vim.fn.readfile(path)")
      )
      assert.are.same(
        { "core/breadcrumbs.lua:1 (readfile)" },
        offenders_of("core/breadcrumbs.lua", "local l = vim.fn.readfile(path)")
      )
      assert.are.same(
        { "test/runner.lua:1 (readblob)" },
        offenders_of("test/runner.lua", "local l = vim.fn.readblob(path)")
      )
    end)

    it("grants the disk exception to the file that has it and to no other", function()
      assert.are.same({}, offenders_of("adapter/install.lua", 'local f = io.open(path, "rb")'))
      assert.are.same(
        { "adapter/install.lua:1 (readfile)" },
        offenders_of("adapter/install.lua", "local l = vim.fn.readfile(path)")
      )
      assert.are.same(
        { "adapter/log.lua:1 (io.open (read mode))" },
        offenders_of("adapter/log.lua", 'local f = io.open(path, "rb")')
      )
    end)

    it("lets core/mirror.lua use only the routes it needs", function()
      assert.are.same({}, offenders_of(MIRROR, "return api.nvim_buf_get_lines(bufnr, 0, -1, false)"))
      assert.are.same({}, offenders_of(MIRROR, "local ok, content = pcall(vim.fn.readfile, path)"))
      assert.are.same({ MIRROR .. ":1 (getbufline)" }, offenders_of(MIRROR, "return vim.fn.getbufline(bufnr, 1, '$')"))
    end)

    local READS = {
      { "nvim_buf_get_lines", "local l = vim.api.nvim_buf_get_lines(b, 0, -1, false)" },
      { "nvim_buf_get_text", "local t = vim.api.nvim_buf_get_text(b, 0, 0, -1, -1, {})" },
      { "getbufline", "local l = vim.fn.getbufline(b, 1, '$')" },
      { "getbufoneline", "local l = vim.fn.getbufoneline(b, 1)" },
      { "getline", "local l = vim.fn.getline(1, '$')" },
      { "get_node_text", "local t = vim.treesitter.get_node_text(node, b)" },
      { "readfile", "local l = vim.fn.readfile(path)" },
      { "readblob", "local l = vim.fn.readblob(path)" },
      { "fs_read", "uv.fs_read(fd, 4096, 0, cb)" },
      { "io.lines", "for l in io.lines(path) do end" },
      { "io.open (read mode)", "local f = io.open(path)" },
      { "io.open (read mode)", 'local f = io.open(path, "r")' },
      { "io.open (read mode)", 'local f = assert(io.open(path, "rb"))' },
      { "io.open (read mode)", 'local f = io.open(path, "r+")' },
      { "io.open (read mode)", "local f = io.open(path, mode)" },
      { "io.open (read mode)", 'local f = io.open("a.txt")' },
      { "io.open (read mode)", "local f = io.open(" },
    }
    for _, case in ipairs(READS) do
      it(("forbids %s in any other file: %s"):format(case[1], case[2]), function()
        assert.are.same({ "x/other.lua:1 (" .. case[1] .. ")" }, offenders_of("x/other.lua", case[2]))
      end)
    end

    local NOT_READS = {
      { "a write mode of io.open", 'local f = io.open(path, "w")' },
      { "a binary write mode of io.open", 'local f = io.open(path, "wb")' },
      { "an append mode of io.open", "local f, err = io.open(log_file_path, 'a')" },
      { "a comment line", "-- vim.fn.readfile(path) would read it" },
      { "an indented comment line", "    --- uses nvim_buf_get_lines" },
      { "a longer identifier", "local lines = getlines(b)" },
      { "a name that merely contains a route", "local x = my_readfile(path)" },
      { "a directory read", "local d = uv.fs_readdir(handle)" },
    }
    for _, case in ipairs(NOT_READS) do
      it(("does not flag %s"):format(case[1]), function()
        assert.are.same({}, offenders_of("x/other.lua", case[2]))
      end)
    end
  end)

  it("mirror.lines returns the buffer text as a fresh table", function()
    local mirror = require("mdview.core.mirror")
    local buf = vim.api.nvim_create_buf(false, true)
    -- A failing assertion must not leave the scratch buffer behind: the state
    -- guard names every leak, and leaks keep that guard from being promoted
    -- from "warn" to "error".
    local ok, err = pcall(function()
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
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    if not ok then
      error(err, 0)
    end
  end)
end)

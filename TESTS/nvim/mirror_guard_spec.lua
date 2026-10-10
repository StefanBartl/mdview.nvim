---@module 'tests.nvim.mirror_guard_spec'
-- Guard against regression: the text for the preview, from a buffer or from a
-- file, must come from mdview.core.mirror. Any KNOWN raw read route under
-- lua/mdview (the buffer API, the file API, the Vimscript and luv equivalents of
-- both, an external reader such as `cat`, an ex `:read`) is a stray read that a
-- future transform (display language) would miss.
--
-- This is a denylist over source lines, a tripwire and not a proof: it cannot
-- see a route it does not list, a call split over several lines, or a function
-- reached through a name built at run time. It catches the honest mistake (and
-- the lazy alias: `local open = io.open`, `pcall(io.open, ...)`), not an
-- attempt to hide a read. A new route that turns up gets a rule and a case below.
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
--- is not visible, so it is not assumed to be a write). `io.open` handed on as a
--- value (`pcall(io.open, path, "r")`, `local open = io.open`) counts too: a
--- literal write mode in the `pcall` is understood, an alias never is.
---@param line string
---@return boolean
local function io_open_reads(line)
  local call = line:match("%f[%w_]io%.open%s*(%b())")
  if call then
    local mode = call:match(",%s*[\"']([^\"']*)[\"']%s*%)$")
    return not (mode and mode:match("^[wa]") ~= nil)
  end
  if line:find("%f[%w_]io%.open%s*%(") then
    return true
  end
  if not line:find("%f[%w_]io%.open%f[^%w_]") then
    return false
  end
  local args = line:match("pcall%s*%(%s*io%.open%s*,(.-)%)")
  local mode = args and args:match(",%s*[\"']([^\"']*)[\"']%s*$")
  return not (mode and mode:match("^[wa]") ~= nil)
end

--- Tools whose job is to print a file.
local READER_TOOLS = { "cat", "head", "tail", "more", "less", "Get-Content", "type", "gc" }

--- A source line starts an external program that prints a file: `systemlist("cat x")`,
--- `vim.system({ "cat", path })`, `io.popen("type x")`. A string literal that is
--- exactly a reader tool counts on its own (the argv is often split over lines);
--- the tools that are also everyday words (`type`, `gc`) only inside a command string.
---@param line string
---@return boolean
local function external_reader(line)
  for _, tool in ipairs(READER_TOOLS) do
    local quoted = "[\"']" .. tool:gsub("%p", "%%%0") .. "[\"']"
    if tool ~= "type" and tool ~= "gc" and line:find(quoted) then
      return true
    end
    local in_command = "system%w*%s*%(%s*[\"']%s*" .. tool:gsub("%p", "%%%0") .. "%s"
    local in_popen = "popen%s*%(%s*[\"']%s*" .. tool:gsub("%p", "%%%0") .. "%s"
    if line:find(in_command) or line:find(in_popen) then
      return true
    end
  end
  return false
end

--- A source line runs an ex command that reads a file or a command's output
--- into the buffer: `vim.cmd("read x")`, `:0r !cat x`, `vim.cmd.read(...)`.
---@param line string
---@return boolean
local function ex_read(line)
  if line:find("vim%.cmd%.r[ea]*d?%f[^%w_]") then
    return true
  end
  if not (line:find("vim%.cmd") or line:find("nvim_command") or line:find("nvim_exec")) then
    return false
  end
  return line:find("[\"']%s*[%d%$%%%.,']*%s*r[ea]*d?[ !]") ~= nil
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
  { route = "nvim_get_current_line", hit = word("nvim_get_current_line"), allowed = {} },
  { route = "getregion", hit = word("getregion"), allowed = {} },
  { route = "getregionpos", hit = word("getregionpos"), allowed = {} },
  { route = "matchbufline", hit = word("matchbufline"), allowed = {} },
  -- The disk side: a file that is not open in a buffer is read by mirror.lines_for_path.
  { route = "readfile", hit = word("readfile"), allowed = { MIRROR } },
  { route = "readblob", hit = word("readblob"), allowed = {} },
  { route = "fs_read", hit = word("fs_read"), allowed = {} },
  { route = "io.lines", hit = word("io.lines"), allowed = {} },
  { route = "io.input", hit = word("io.input"), allowed = {} },
  { route = "io.read", hit = word("io.read"), allowed = {} },
  { route = "io.popen", hit = word("io.popen"), allowed = {} },
  { route = "vim.secure.read", hit = word("vim.secure.read"), allowed = {} },
  { route = "external reader (cat, type, …)", hit = external_reader, allowed = {} },
  { route = "ex :read", hit = ex_read, allowed = {} },
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
      { "nvim_get_current_line", "local l = vim.api.nvim_get_current_line()" },
      { "getregion", "local r = vim.fn.getregion(a, b)" },
      { "getregionpos", "local r = vim.fn.getregionpos(a, b)" },
      { "matchbufline", "local m = vim.fn.matchbufline(b, 'x', 1, '$')" },
      { "vim.secure.read", "local t = vim.secure.read(path)" },
      { "io.input", "io.input(path)" },
      { "io.read", "local t = io.read('a')" },
      { "io.popen", "local p = io.popen('ls')" },
      { "io.open (read mode)", 'local ok, f = pcall(io.open, path, "r")' },
      { "io.open (read mode)", "local ok, f = pcall(io.open, path)" },
      { "io.open (read mode)", "local open = io.open" },
      { "external reader (cat, type, …)", 'local l = vim.fn.systemlist("cat " .. path)' },
      { "external reader (cat, type, …)", 'local l = vim.fn.system("type " .. path)' },
      { "external reader (cat, type, …)", 'vim.system({ "cat", path }, {}, cb)' },
      { "external reader (cat, type, …)", '  "Get-Content",' },
      { "ex :read", 'vim.cmd("read " .. vim.fn.fnameescape(path))' },
      { "ex :read", 'vim.cmd("0r " .. path)' },
      { "ex :read", 'vim.cmd("$read !cat x")' },
      { "ex :read", "vim.cmd.read(path)" },
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
      { "a pcall of io.open in write mode", 'local ok, f = pcall(io.open, path, "w")' },
      { "a pcall of io.open in append mode", "local ok, f = pcall(io.open, path, 'a')" },
      { "a field called type", 'local t = { "type", "name" }' },
      { "a command that is not a reader", 'vim.system({ "curl", url }, {}, cb)' },
      { "an ex command that merely contains read", 'vim.cmd("setlocal readonly")' },
      { "an ex command that is not read", 'vim.cmd("redraw")' },
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

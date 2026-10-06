---@module 'tests.nvim.mirror_exact_path_spec'
-- mirror.lines_for_path must find the buffer that has EXACTLY this file open.
-- It used to hand the path to `vim.fn.bufnr()`, which reads its argument as a
-- FILE PATTERN: it matches anywhere in a buffer name (so `a.md` found a loaded
-- `<other dir>/a.md` or `xa.md` or `a.md.bak`), a relative argument was never
-- made absolute (`:MDView start a.md` passes it on as typed), and `[ { ~ * ? %
-- #` in a name are pattern syntax (`%` is even the current buffer). The preview
-- then showed the text of another document. The buffers here are named scratch
-- buffers: a name is all the lookup looks at, and they load no filetype/syntax.

---@diagnostic disable: undefined-global

local mirror = require("mdview.core.mirror")

---@class MirrorPathSandbox
---@field path fun(rel: string): string # absolute path under the sandbox root
---@field file fun(rel: string, lines: string[]): string # write a file, return its path
---@field buf fun(rel: string, lines: string[]): integer # loaded scratch buffer named like `rel`
---@field cd fun(rel: string): nil

--- Runs `fn(sb)` in a temporary directory; the files, the buffers and the cwd
--- are restored even when an assertion in `fn` throws (a leaked scratch buffer
--- would keep the state guard from being promoted from "warn" to "error").
---@param fn fun(sb: MirrorPathSandbox)
---@return nil
local function sandbox(fn)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local previous_cwd = vim.fn.getcwd()
  local buffers = {}

  ---@type MirrorPathSandbox
  local sb = {
    path = function(rel)
      return root .. "/" .. rel
    end,
    file = function(rel, lines)
      local path = root .. "/" .. rel
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      assert.are.equal(0, vim.fn.writefile(lines, path))
      return path
    end,
    buf = function(rel, lines)
      local buf = vim.api.nvim_create_buf(false, true)
      buffers[#buffers + 1] = buf
      vim.api.nvim_buf_set_name(buf, root .. "/" .. rel)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      return buf
    end,
    cd = function(rel)
      vim.fn.mkdir(root .. "/" .. rel, "p")
      assert.are_not.equal("", vim.fn.chdir(root .. "/" .. rel))
    end,
  }

  local ok, err = pcall(fn, sb)
  vim.fn.chdir(previous_cwd)
  for _, buf in ipairs(buffers) do
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  vim.fn.delete(root, "rf")
  if not ok then
    error(err, 0)
  end
end

describe("mdview.core.mirror.lines_for_path matches the buffer exactly", function()
  it("a relative name is the file in the cwd, not a loaded buffer of that name in another directory", function()
    sandbox(function(sb)
      sb.file("A/a.md", { "CWD FILE" })
      sb.buf("sub/a.md", { "OTHER" })
      sb.cd("A")
      assert.are.same({ "CWD FILE" }, mirror.lines_for_path("a.md"))
    end)
  end)

  it("a relative name finds the unsaved buffer of the cwd file, even next to a same-named buffer elsewhere", function()
    sandbox(function(sb)
      sb.file("A/a.md", { "ON DISK" })
      sb.buf("A/a.md", { "UNSAVED" })
      sb.buf("sub/a.md", { "OTHER" })
      sb.cd("A")
      assert.are.same({ "UNSAVED" }, mirror.lines_for_path("a.md"))
      assert.are.same({ "UNSAVED" }, mirror.lines_for_path("./a.md"))
    end)
  end)

  it("a buffer whose name merely ends with the file name is not that file", function()
    sandbox(function(sb)
      sb.file("A/a.md", { "CWD FILE" })
      sb.buf("A/xa.md", { "SUFFIX" })
      sb.cd("A")
      assert.are.same({ "CWD FILE" }, mirror.lines_for_path("a.md"))
    end)
  end)

  it("a buffer whose name merely starts with the file name is not that file", function()
    sandbox(function(sb)
      local path = sb.file("A/a.md", { "CWD FILE" })
      sb.buf("A/a.md.bak", { "PREFIX" })
      assert.are.same({ "CWD FILE" }, mirror.lines_for_path(path))
    end)
  end)

  it("a name that is a pattern for the current buffer is only the file of that name", function()
    sandbox(function(sb)
      sb.file("A/%", { "PERCENT FILE" })
      sb.cd("A")
      -- `bufnr("%")` is the current buffer; here that is a buffer with other text.
      local current = vim.api.nvim_get_current_buf()
      local previous = vim.api.nvim_buf_get_lines(current, 0, -1, false)
      vim.api.nvim_buf_set_lines(current, 0, -1, false, { "CURRENT BUFFER" })
      local ok, got = pcall(mirror.lines_for_path, "%")
      vim.api.nvim_buf_set_lines(current, 0, -1, false, previous)
      assert.is_true(ok, tostring(got))
      assert.are.same({ "PERCENT FILE" }, got)
    end)
  end)

  -- Names that are legal on every platform. Each has a file on disk with other
  -- text than the loaded buffer: the answer must be the unsaved buffer.
  for _, name in ipairs({ "w[i]rd.md", "br{ace}.md", "til~de.md", "per%cent.md", "ha#sh.md", "sp ace.md" }) do
    it(("finds the loaded buffer of a file named %q"):format(name), function()
      sandbox(function(sb)
        local path = sb.file("A/" .. name, { "ON DISK" })
        sb.buf("A/" .. name, { "UNSAVED" })
        assert.are.same({ "UNSAVED" }, mirror.lines_for_path(path))
        sb.cd("A")
        assert.are.same({ "UNSAVED" }, mirror.lines_for_path(name))
      end)
    end)
  end

  -- The other direction: a file that is not open anywhere, whose name read as a
  -- pattern matches the loaded buffer next to it. Its answer is the file.
  ---@type string[][]
  local pairs_of_pattern_and_decoy = {
    { "w[i]rd.md", "wird.md" },
    { "fo{o,b}.md", "foo.md" },
  }
  if vim.fn.has("win32") == 0 then
    -- `*` and `?` cannot be in a file name on Windows.
    pairs_of_pattern_and_decoy[#pairs_of_pattern_and_decoy + 1] = { "st*r.md", "star.md" }
    pairs_of_pattern_and_decoy[#pairs_of_pattern_and_decoy + 1] = { "qu?te.md", "quite.md" }
  end
  for _, pair in ipairs(pairs_of_pattern_and_decoy) do
    local name, decoy = pair[1], pair[2]
    it(("a file named %q is not the loaded buffer %q its name would match as a pattern"):format(name, decoy), function()
      sandbox(function(sb)
        local path = sb.file("A/" .. name, { "ON DISK" })
        sb.buf("A/" .. decoy, { "DECOY" })
        assert.are.same({ "ON DISK" }, mirror.lines_for_path(path))
        sb.cd("A")
        assert.are.same({ "ON DISK" }, mirror.lines_for_path(name))
      end)
    end)
  end

  -- `*` and `?` cannot be in a file name on Windows, but a buffer may be named
  -- like that on every platform, so the buffer side is checked everywhere.
  for _, name in ipairs({ "star*.md", "quest?on.md", "st*r?.md" }) do
    it(("finds the loaded buffer named %q"):format(name), function()
      sandbox(function(sb)
        sb.buf("A/" .. name, { "UNSAVED " .. name })
        -- A decoy that the name would match if it were read as a pattern.
        sb.buf("A/starXX.md", { "DECOY" })
        sb.buf("A/questXon.md", { "DECOY" })
        assert.are.same({ "UNSAVED " .. name }, mirror.lines_for_path(sb.path("A/" .. name)))
      end)
    end)
  end

  it("is the same buffer for the native and for the slash-unified spelling of the path", function()
    sandbox(function(sb)
      local path = sb.file("A/same.md", { "ON DISK" })
      sb.buf("A/same.md", { "UNSAVED" })
      assert.are.same({ "UNSAVED" }, mirror.lines_for_path(vim.fn.fnamemodify(path, ":p")))
      assert.are.same({ "UNSAVED" }, mirror.lines_for_path((path:gsub("\\", "/"))))
      if vim.fn.has("win32") == 1 then
        -- Only there is a backslash a separator.
        assert.are.same({ "UNSAVED" }, mirror.lines_for_path((path:gsub("/", "\\"))))
      end
    end)
  end)

  it("ignores the case of a name when 'fileignorecase' is set", function()
    local previous = vim.o.fileignorecase
    vim.o.fileignorecase = true
    local ok, err = pcall(function()
      sandbox(function(sb)
        sb.buf("A/CaseDoc.md", { "UNSAVED" })
        assert.are.same({ "UNSAVED" }, mirror.lines_for_path(sb.path("A/casedoc.md")))
      end)
    end)
    vim.o.fileignorecase = previous
    if not ok then
      error(err, 0)
    end
  end)

  it("answers {} for a relative name nobody has, even when another directory has a buffer of that name", function()
    sandbox(function(sb)
      sb.buf("sub/ghost.md", { "OTHER" })
      sb.cd("A")
      assert.are.same({}, mirror.lines_for_path("ghost.md"))
    end)
  end)
end)

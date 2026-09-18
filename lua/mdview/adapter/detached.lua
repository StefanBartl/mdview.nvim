---@module 'mdview.adapter.detached'
--- Spawns processes that must OUTLIVE this Neovim instance.
---
--- Deliberately separate from mdview.adapter.runner rather than a flag on it:
--- runner's relay child is bound to this instance on purpose (VimLeavePre kills
--- it, stdout is piped into the log buffer, state tracks the handle). A detached
--- process needs the exact opposite of all three — no parent link, no pipes to
--- keep open, no state entry to go stale once we exit. Mixing the two into one
--- function would mean every caller has to get three unrelated flags right.

---@diagnostic disable: undefined-field

-- DEP-01: matches the fallback pattern every other module in this repo
-- already uses -- this repo's stated floor is 0.9+, so a bare vim.uv would
-- break on Neovim < 0.10.
local uv = vim.uv or vim.loop
local expand_path = require("lib.nvim.cross.fs.expand_path")

local M = {}

--- Build the child's environment as libuv wants it (a list of "KEY=VALUE"),
--- inheriting this process's environment and layering `extra` on top.
---
--- Passing an explicit env rather than mutating `vim.env` around the spawn is
--- deliberate: `vim.env.X = nil` genuinely unsets a variable, so a
--- save-and-restore around the call cannot distinguish "was unset" from "was
--- absent from my restore table" and would leak the override into this
--- instance's own environment.
---@param extra table<string, string>|nil
---@return string[]|nil # nil when there is nothing to add (inherit as-is)
function M.build_env(extra)
  if not extra or vim.tbl_isempty(extra) then
    return nil
  end

  local merged = vim.fn.environ()
  for k, v in pairs(extra) do
    merged[k] = v
  end

  local out = {}
  for k, v in pairs(merged) do
    out[#out + 1] = ("%s=%s"):format(k, v)
  end
  return out
end

--- Spawn `cmd` with `args` fully detached: it survives `:qa` of this instance,
--- and its stdio is discarded rather than piped (nothing here will be alive to
--- read it, and an unread pipe eventually blocks the child's writes).
---@param cmd string # executable name or absolute path
---@param args string[] # argument vector
---@param cwd string|nil # working directory for the child
---@param extra_env table<string, string>|nil # vars added on top of the inherited environment
---@return integer|nil pid, string|nil err
function M.spawn(cmd, args, cwd, extra_env)
  if type(cmd) ~= "string" or cmd == "" then
    return nil, "invalid command: " .. tostring(cmd)
  end

  -- luv's meta declares every uv.spawn option required (uid, gid, verbatim,
  -- hide and, here, the ones already set below), which no real caller passes.
  ---@diagnostic disable-next-line: missing-fields
  local handle, pid = uv.spawn(cmd, {
    args = args or {},
    cwd = cwd,
    env = M.build_env(extra_env),
    -- detached: the child gets its own process group, so it is not killed
    -- with us and is not attached to our terminal's signals.
    detached = true,
    -- No pipes: the child's output goes nowhere. Background instances log
    -- to a file instead (minimal_init.lua turns file_log on for exactly
    -- this reason), which is readable after the fact.
    stdio = { nil, nil, nil },
  }, function() end)

  if not handle then
    -- uv.spawn returns (nil, "ENOENT: ...") — the second value is the error.
    return nil, tostring(pid)
  end

  -- unref, then close: unref drops the handle from the event loop's refcount
  -- so it can't keep this instance alive at exit, and closing it releases our
  -- side without signalling the (already independent) child.
  pcall(function()
    handle:unref()
    handle:close()
  end)

  ---@cast pid integer
  return pid, nil
end

--- The one spelling this module uses for a file path.
---
--- Absolute is not the same as canonical. On macOS the temp dir, /tmp and
--- /var are symlinks into /private, and the OS reports only the resolved
--- form — so the two routes into resolve_target below used to disagree about
--- the very same file:
---   * a RELATIVE arg gets the cwd prepended by `:p`, and the cwd comes back
---     from the OS already resolved  -> /private/var/folders/.../notes.md
---   * a buffer name is resolved by Neovim itself (fix_fname on Unix)
---                                                -> /private/var/.../notes.md
---   * an ALREADY-absolute arg is left exactly as typed by `:p`
---                                                ->         /var/.../notes.md
--- A key that depends on which call produced it is not a key (XP-02), and
--- standalone.lua compares this value against the current buffer's path.
--- Resolving symlinks explicitly collapses all three routes onto the spelling
--- Neovim already uses for buffer names — which is what the rest of the
--- plugin keys preview rooms by (mdview.helper.target_key -> normalize.path
--- of a buffer name). Resolving is also the only direction that exists:
--- nothing can map /private/var back to /var.
---
--- Deliberately here and not inside mdview.helper.normalize: this touches the
--- filesystem, and normalize.path() runs in the per-keystroke push path
--- (live_push / scroll_sync). This runs once per `:MDView standalone`.
---@param path string|nil # a real path; `~`/`$VAR` expansion is the caller's job
---@return string|nil # nil only for a nil/empty path
function M.canonical_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local abs = vim.fn.fnamemodify(path, ":p")
  -- fs_realpath answers nil for anything it cannot stat (nonexistent file,
  -- unreadable parent). The absolute form is then still the best available
  -- answer; rejecting a genuinely missing file is resolve_target's job, and
  -- it reports the path it actually looked at.
  return vim.fs.normalize(uv.fs_realpath(abs) or abs)
end

--- Resolve the file a standalone preview should target: the explicit argument
--- if given, else the current buffer's file. Returns nil for an unnamed buffer,
--- since a background process has no buffer to read and needs a real path.
---
--- The result is canonical (see M.canonical_path): the same file yields the
--- same string whether it was named relatively, absolutely, or not at all.
---@param arg string|nil
---@return string|nil path, string|nil err
function M.resolve_target(arg)
  local path
  if arg and arg ~= "" then
    -- expand_path() only on a user-typed arg, which may carry `~` or `$VAR`; a
    -- buffer name is already a literal path and must not be re-expanded.
    -- Pure string substitution, not vim.fn.expand(): no &shell backtick
    -- execution and no `%`/`#`/`<cfile>` special-name resolution (SEC-34).
    path = M.canonical_path(expand_path(arg))
  else
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    if name == "" then
      return nil, "current buffer has no file — pass a path, e.g. :MDView standalone README.md"
    end
    path = M.canonical_path(name)
  end

  if not path or vim.fn.filereadable(path) ~= 1 then
    return nil, "not a readable file: " .. tostring(path)
  end
  return path, nil
end

return M

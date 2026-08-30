---@module 'mdview.bindings.usrcmds.standalone'
--- Action behind :MDView standalone — hand a file to the relay binary's own
--- watch mode and step out of the way entirely.
---
--- It leaves no Neovim in the chain at all: the relay watches the file on disk
--- itself and broadcasts changes straight to the browser, so the preview
--- outlives `:qa` and can't be taken down by anything happening in the editor.
--- The trade-off is deliberate — it previews the file as SAVED: no
--- unsaved-buffer push, no scroll sync, no cursor marker (nothing that requires
--- knowing where a cursor is). In exchange it costs one small process and keeps
--- running no matter what happens to any editor.
---
--- (An earlier `:MDView detach` kept a headless Neovim in the chain to preserve
--- those live features; it was removed because a detached headless instance is
--- never edited, so live push never actually reached it — it was a static
--- snapshot dominated by this command. See docs/standalone.md.)
---
--- Use it for a reference document you want open beside your work, or to share
--- a rendered doc with something that isn't Neovim.

local detached = require("mdview.adapter.detached")
local install = require("mdview.adapter.install")
local log = require("mdview.helper.log")

local notify = require("lib.nvim.notify").create("").notify

local M = {}

--- Does `bin` understand --watch?
---
--- Worth checking before spawning: standalone mode needs a relay built with
--- watch support (v0.3.0+), but the binary on disk is whatever `install.version`
--- pinned. An older one rejects the flag and exits instantly — and since a
--- detached process has no pipes, that failure is completely silent. Probing
--- turns "nothing happened, no idea why" into an actionable message.
---
--- Go's flag package prints its usage (which lists every defined flag) to
--- stderr and exits non-zero for an unknown flag, so an unknown-flag probe is
--- itself the capability check.
---@internal
---@param bin string
---@return boolean
--- Probing spawns the relay once. It used to run through vim.fn.system(),
--- which blocked the UI thread for the whole (short, but non-zero) lifetime of
--- that process; vim.system() reports back via callback instead. The verdict is
--- memoised per binary path -- a given binary's flag set does not change while
--- Neovim is running -- so repeated `:MDView standalone` calls probe once.
---@internal
---@type table<string, boolean>
local watch_support_cache = {}

---@internal
---@param bin string
---@param cb fun(supported: boolean)
local function supports_watch(bin, cb)
  local cached = watch_support_cache[bin]
  if cached ~= nil then
    cb(cached)
    return
  end

  local function record(out)
    local supported = type(out) == "string" and out:find("-watch", 1, true) ~= nil
    watch_support_cache[bin] = supported
    cb(supported)
  end

  if not vim.system then
    record(vim.fn.system({ bin, "--mdview-capability-probe" }))
    return
  end

  vim.system({ bin, "--mdview-capability-probe" }, { text = true }, function(res)
    -- Go's flag package writes the usage listing to stderr; keep both
    -- streams so the probe works regardless of where it lands.
    local out = (res.stdout or "") .. (res.stderr or "")
    vim.schedule(function()
      record(out)
    end)
  end)
end

--- The relay binary to use for standalone mode, in precedence order: an explicit
--- `standalone.binary_path` override, then a build inside this checkout
--- (zero-config — and it's --watch-capable, which the pinned release may not be),
--- then the installed release.
---@internal
---@return string|nil path, string|nil err
local function resolve_binary()
  local cfg = require("mdview.config").defaults.standalone or {}
  local server_args = require("mdview.adapter.server_args")
  local override = cfg.binary_path
  if type(override) == "string" and override ~= "" then
    local path = vim.fn.expand(override)
    -- spawnable(), not executable(): on Windows an extension-less file passes
    -- the latter and still spawns as ENOENT (see server_args).
    local usable = server_args.spawnable(path)
    if not usable then
      return nil,
        ("standalone.binary_path is not spawnable: %s (looked for %s)"):format(path, server_args.built_binary_name())
    end
    return usable, nil
  end
  local built = server_args.local_built_binary()
  if built then
    return built, nil
  end
  return install.ensure_binary()
end

--- Start the relay in standalone watch mode for `file` (default: the current
--- buffer's file).
---   :MDView standalone
---   :MDView standalone notes.md
---   :MDView standalone notes.md --no-browser
---@param file_arg string|nil # path from the route's `file` arg
---@param no_browser boolean|nil # true when --no-browser was passed
function M.run(file_arg, no_browser)
  local target, err = detached.resolve_target(file_arg)
  if not target then
    notify("[mdview] standalone: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  -- Standalone previews the file as it is *on disk*. Warning here rather than
  -- silently previewing stale content is the honest thing: the user asked for
  -- this file and would otherwise wonder why their edits don't show up.
  if vim.bo.modified and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p") == target then
    notify(
      "[mdview] standalone previews the file on disk — unsaved changes in this buffer won't appear until you :write",
      vim.log.levels.WARN
    )
  end

  local bin, bin_err = resolve_binary()
  if not bin then
    notify("[mdview] standalone: " .. tostring(bin_err), vim.log.levels.ERROR)
    return
  end

  -- The capability probe is asynchronous now, so everything that depends on
  -- its verdict moved into this continuation. Nothing else changed about the
  -- ordering: probe first, bail out on an old binary, otherwise carry on.
  supports_watch(bin, function(supported)
    if not supported then
      notify(
        ("[mdview] standalone: this relay binary has no --watch support.\n%s\nIt needs mdview-server v0.3.0+. Either bump install.version, or point standalone.binary_path at a newer/locally built relay."):format(
          bin
        ),
        vim.log.levels.ERROR
      )
      return
    end

    local web_root, web_err = install.ensure_client_bundle()
    if not web_root then
      notify("[mdview] standalone: " .. tostring(web_err), vim.log.levels.ERROR)
      return
    end

    local defaults = require("mdview.config").defaults
    local browser_defaults = require("mdview.config.browser").defaults

    -- Generate the token here rather than letting the relay mint its own: a
    -- detached process's stdout goes nowhere, so if the relay chose the token we
    -- could never tell the user the preview URL. That matters for --no-browser,
    -- whose whole point is opening the preview yourself (or from another device).
    local token = require("mdview.helper.gen_token")()
    local port = (defaults.server_port or 43219) + 100
    local theme = tostring(browser_defaults.theme or "github")
    local highlighter = tostring(browser_defaults.highlighter or "hljs")

    local args = {
      "--watch",
      target,
      "--token",
      token,
      "--web-root",
      web_root,
      -- Offset well clear of both server_port and dev_server_port
      -- (server_port + 1 by default): a standalone preview is meant to sit
      -- alongside a normal session, so it must not compete for the relay's
      -- port, nor land on the Vite dev port during development. The relay's
      -- FindFreePort still walks upward from here if this one is taken.
      "--port",
      tostring(port),
      "--theme",
      theme,
      "--hl",
      highlighter,
    }
    if no_browser then
      args[#args + 1] = "--open=false"
    end

    local pid, spawn_err = detached.spawn(bin, args, vim.fn.fnamemodify(target, ":h"))
    if not pid then
      notify("[mdview] standalone: failed to spawn relay: " .. tostring(spawn_err), vim.log.levels.ERROR)
      return
    end

    local url = ("http://localhost:%d/?key=%s&token=%s&theme=%s&hl=%s"):format(
      port,
      require("mdview.helper.normalize").path_for_url(target),
      vim.uri_encode(token),
      vim.uri_encode(theme),
      vim.uri_encode(highlighter)
    )

    log.debug(("standalone: spawned pid %d for %s at %s"):format(pid, target, url), nil, "usercmds.standalone", true)

    local msg = ("[mdview] standalone preview started (pid %d) for %s\nNo Neovim involved — it follows the file on disk. Stop it by killing the pid."):format(
      pid,
      vim.fn.fnamemodify(target, ":t")
    )
    if no_browser then
      -- Nothing opened a tab, so the URL is the only way in. Port is the
      -- requested one; the relay walks upward if it was taken.
      msg = msg .. ("\nOpen: %s\n(if port %d was taken, the relay picked the next free one)"):format(url, port)
    end
    notify(msg, vim.log.levels.INFO)
  end)
end

return M

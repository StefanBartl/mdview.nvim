---@module 'mdview.adapter.server_args'
-- Resolves the (cmd, args, cwd) triple used to spawn the native
-- mdview-server process: ensures the platform binary and client bundle are
-- installed, generates a fresh per-session token, and stores it in state so
-- ws_client can attach it to /update and the browser tab can attach it to /ws.

local install = require("mdview.adapter.install")
local gen_token = require("mdview.helper.gen_token")
local notify = require("lib.nvim.notify").create("").notify

local M = {}

--- Absolute path to this mdview.nvim checkout, derived from this file's own
--- location (<root>/lua/mdview/adapter/server_args.lua). Lets the plugin find a
--- build sitting inside its own checkout without the user hardcoding a path.
---@return string
local function plugin_root()
  local this = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.normalize(vim.fn.fnamemodify(this, ":p:h:h:h:h"))
end

--- A relay binary built inside this checkout, if one exists. This is the
--- zero-config dev path: `npm run build:go` writes `native/server/mdview-server`
--- (Go keeps the exact -o name, so no `.exe` on Windows), and a checkout that
--- has it is by definition a dev checkout — a normal lazy/packer install never
--- ships one (it's gitignored). So auto-using it is safe: it only ever triggers
--- when a build is actually present.
---@return string|nil
local function local_built_binary()
  local root = plugin_root()
  for _, name in ipairs({ "mdview-server", "mdview-server.exe" }) do
    local p = root .. "/native/server/" .. name
    if vim.fn.executable(p) == 1 then
      return p
    end
  end
  return nil
end
-- Exposed so :MDView standalone can reuse the same zero-config dev build (it
-- also needs a --watch-capable relay, which the local build is and the pinned
-- release may not be).
M.local_built_binary = local_built_binary

--- The client bundle built inside this checkout, if present (`npm run
--- build:client` writes `dist/client`). Same self-gating logic as the binary.
---@return string|nil
local function local_built_web_root()
  local dir = plugin_root() .. "/dist/client"
  if vim.fn.filereadable(dir .. "/index.html") == 1 then
    return dir
  end
  return nil
end

--- Relay binary the normal `:MDView start` path spawns, in precedence order:
--- explicit `dev.binary_path`, then `$MDVIEW_DEV_BINARY` (the only way a
--- detached instance — scripts/minimal_init.lua loads none of the user's Lua
--- config — can reach one), then a build inside this checkout (zero-config dev),
--- then whatever `install` manages (downloaded release).
---@internal
---@return string|nil path, string|nil err
local function resolve_binary()
  local dev = require("mdview.config").defaults.dev or {}
  local override = dev.binary_path
  if not (type(override) == "string" and override ~= "") then
    override = vim.env.MDVIEW_DEV_BINARY
  end
  if type(override) == "string" and override ~= "" then
    local path = vim.fn.expand(override)
    if vim.fn.executable(path) == 1 then
      return path, nil
    end
    -- A stale/typo'd override shouldn't brick start — warn and fall through
    -- to the auto-detected build / release, which usually works.
    notify(("[mdview] dev.binary_path is not executable, ignoring it: %q"):format(path), vim.log.levels.WARN)
  end
  local built = local_built_binary()
  if built then
    return built, nil
  end
  return install.ensure_binary()
end

--- Client bundle dir the normal `:MDView start` path passes as --web-root, same
--- precedence as resolve_binary: `dev.web_root`, `$MDVIEW_DEV_WEB_ROOT`, a build
--- inside this checkout, else whatever `install` manages.
---@internal
---@return string|nil path, string|nil err
local function resolve_web_root()
  local dev = require("mdview.config").defaults.dev or {}
  local override = dev.web_root
  if not (type(override) == "string" and override ~= "") then
    override = vim.env.MDVIEW_DEV_WEB_ROOT
  end
  if type(override) == "string" and override ~= "" then
    local path = vim.fn.expand(override)
    if vim.fn.isdirectory(path) == 1 then
      return path, nil
    end
    notify(("[mdview] dev.web_root is not a directory, ignoring it: %q"):format(path), vim.log.levels.WARN)
  end
  local built = local_built_web_root()
  if built then
    return built, nil
  end
  return install.ensure_client_bundle()
end

--- @param cwd_override string|nil # takes precedence over mdview.config.defaults.server_cwd, e.g. from `:MDViewStart cwd=...`
--- @return string|nil cmd
--- @return string[]|nil args
--- @return string|nil cwd
--- @return string|nil err
function M.resolve(cwd_override)
  local defaults = require("mdview.config").defaults
  local state = require("mdview.core.state")

  local bin_path, bin_err = resolve_binary()
  if not bin_path then
    return nil, nil, nil, "failed to resolve mdview-server binary: " .. tostring(bin_err)
  end

  local web_root, web_err = resolve_web_root()
  if not web_root then
    return nil, nil, nil, "failed to resolve mdview client bundle: " .. tostring(web_err)
  end

  local token = gen_token()
  state.set_token(token)

  local args = {
    "--port",
    tostring(defaults.server_port or 43219),
    "--token",
    token,
    "--web-root",
    web_root,
  }

  -- Opt-in WebTransport (HTTP/3): ask the relay to also serve /wt and print its
  -- cert hash (the runner parses it). Off by default → no UDP listener / no
  -- cert overhead.
  local experimental = defaults.experimental or {}
  if experimental.webtransport == true then
    args[#args + 1] = "--webtransport"
  end

  local cwd = cwd_override
  if not cwd or cwd == "" then
    cwd = defaults.server_cwd
  end

  return bin_path, args, cwd, nil
end

return M

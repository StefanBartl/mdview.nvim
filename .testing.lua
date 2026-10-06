-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "mdview",
  -- Where the specs live (relative to this directory).
  roots = { "TESTS/lua", "TESTS/nvim" },
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "auto",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "file",
  -- "c" = child started from a -c command (v:vim_did_enter is 0, <cword> works),
  -- "l" = `nvim -l`.
  host = "c",
  -- Two cases assert nothing on some platforms (enter_hub_spec "reset() is safe to call twice": the
  -- point is that it does not raise; launcher_url_spec "on other Unix": early return on Windows/macOS).
  -- The specs stay as they are, so such cases pass with a note instead of failing.
  assertions = "warn",
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  env_allow = { "LIB_NVIM_PATH" },
  -- Guards (safety nets around each case, see testing.nvim's docs/GUARDS.md). The suite passes
  -- the fs, prompt, deprecation and scheduled-error guards cleanly, so those fail the case.
  guards = {
    fs = "error",
    prompt = "error",
    deprecation = "error",
    scheduled_error = "error",
    -- The process guard is on: the plugin shells out to curl (see guard_allow.spawn).
    process_net = "error",
    -- Still warn: buffer_switch_spec and pin_spec leave a running `curl -X POST` job to a server
    -- nobody started (real leak of the specs), and several specs leave scratch buffers, windows,
    -- tab pages and plugin autocmd groups behind (harmless under isolated = "file", but named).
    state = "warn",
  },
  -- What the specs may do on purpose.
  guard_allow = {
    -- ws_client pushes buffer content with `curl -X POST` to the local relay; the specs exercise
    -- that transport against a port without a server, so the spawn is the behavior under test.
    spawn = {
      "curl",
      -- browser_args_spec and server_args_spec make a fake executable with `chmod +x` (Unix only),
      -- which is how the specs create the "browser/server binary found on disk" fixture.
      "chmod",
      -- breadcrumbs_spec opens a .py buffer on purpose; Neovim's own python3 ftplugin then probes
      -- the python3 provider (a runtime action, not the plugin's), which only exists on CI runners.
      -- (Neovim tries python3, python and the versioned names in turn, hence the list.)
      "python3",
      "python",
      "python3.9",
      "python3.10",
      "python3.11",
      "python3.12",
      "python3.13",
      "python3.14",
      "python3.15",
    },
  },
}

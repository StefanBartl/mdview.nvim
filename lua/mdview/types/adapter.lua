---@module 'mdview.types.adapter'

-- == log ==
---@class LoggerOptions
---@field debug boolean?         # enable debug output to Neovim stdout
---@field buf_name string?       # override buffer name for the log scratch buffer
---@field file_path string?      # optional file path to append persistent logs


-- == runner ==
---@class SpawnedProcess
---@field handle userdata        # luv handle for the spawned process
---@field pid integer            # process ID
---@field stdout userdata        # stdout pipe handle
---@field stderr userdata        # stderr pipe handle
---@field cwd string             # working directory used for the spawn


-- == browser.init ==
---@class BrowserHandle
---@field job_id number jobstart id
---@field tmp_profile string|nil temporary profile path
---@field cmd string the executable launched
---@field args string[] the args used to start the process
---@field platform "win"|"mac"|"unix"

---@class BrowserOptions
---@field browser_cmd string|nil  # explicit absolute path to the browser executable
---@field browser string|nil      # friendly name (e.g. "chrome", "firefox")
---@field on_exit fun(job_id: integer, exit_code: integer)|nil  # optional callback

-- == browser.resolve_command ==
---@class browser_resolver
---@field try_resolve fun(string): boolean function to test if a candidate command is valid
---@field default_candidates string[] list of fallback browser executable names
---@field browser_cfg table plugin/browser configuration with get_resolved_cmd method
---@field probe_platform_paths fun(): string[] returns platform-specific candidate paths



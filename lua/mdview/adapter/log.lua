---@module 'mdview.adapter.log'
--- Collects logs for mdview server and optionally writes to a scratch buffer or file.
--- Minimal changes: replace deprecated buffer option APIs with nvim_set_option_value,
--- keep behavior and surface stable.

local M = {}

local api = vim.api

-- required config to read debug flag
local cfg_ok, mdview_config = pcall(require, "mdview.config")

---@type boolean
local DEBUG = (cfg_ok and mdview_config and mdview_config.defaults and mdview_config.defaults.debug) or false

---@type string
local LOG_BUF_NAME = (cfg_ok and mdview_config and mdview_config.defaults and mdview_config.defaults.log_buffer_name)	or "mdview://logs"

---@type string[]
local log_lines = {}

---@type string|nil
local log_file_path = "./debuglog" -- optional file path for persistent logs AUDIT: Nach Development Phase auf üblichen Logfolder ändern, zb stdpath('data')

--- Configure the logger.
--- @param debug boolean? enable debug output to Neovim stdout
--- @param buf_name string? override buffer name for the log scratch buffer
--- @param file_path string? optional file path to append persistent logs
function M.setup(debug, buf_name, file_path)
  DEBUG = debug or false
  LOG_BUF_NAME = buf_name or LOG_BUF_NAME
  log_file_path = file_path
end

--- Append a line to the in-memory log store and optionally to a file.
--- Strips common ANSI escape sequences and splits on line breaks.
--- @param line string
--- @param prefix string? optional prefix to prepend to each line
function M.append(line, prefix)
  if not line then return end
  if prefix then line = prefix .. " " .. line end

  -- strip ANSI escape sequences (basic set)
  line = line:gsub("%z", ""):gsub("\27%[[%d;]*m", ""):gsub("\27%]%d+;.-\7", ""):gsub("\27%[?%d+;?%d*%p?", "")

  for l in line:gmatch("([^\n\r]+)") do
    -- append to sequential table to avoid reallocations
    log_lines[#log_lines + 1] = l

    -- maintain cap of recent lines (ring behaviour by dropping oldest)
    if #log_lines > 2000 then
      table.remove(log_lines, 1)
    end

    if DEBUG then
      vim.schedule(function()
			api.nvim_echo({ { l, nil } }, true, {})
      end)
    end

    -- optional: append to persistent file
    if log_file_path then
      local fd, err = io.open(log_file_path, "a")
      if fd then
        fd:write(l .. "\n")
        fd:close()
      else
        -- non-fatal: debug notify if configured
        if DEBUG then
          vim.schedule(function()
            api.nvim_echo({ { ("mdview.log: failed to write to %s: %s"):format(tostring(log_file_path), tostring(err)), "ErrorMsg" } }, true, { err = true })
          end)
        end
      end
    end
  end
end

--- Show the log buffer in the current window, creating it if necessary.
function M.show()
  vim.schedule(function()
    local buf = nil

    for _, b in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_valid(b) and api.nvim_buf_get_name(b) == LOG_BUF_NAME then
        buf = b
        break
      end
    end

    if not buf then
      buf = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(buf, LOG_BUF_NAME)

      -- set buffer-local options using modern helper
      api.nvim_set_option_value("buftype", "nofile", { scope = "local", buf = buf })
      api.nvim_set_option_value("bufhidden", "wipe", { scope = "local", buf = buf })
      -- keep buffer unlisted by default (do not expose in buffer lists)
      api.nvim_set_option_value("buflisted", false, { scope = "local", buf = buf })
    end

    -- allow writing lines, then make read-only again
    api.nvim_set_option_value("modifiable", true, { scope = "local", buf = buf })
    api.nvim_buf_set_lines(buf, 0, -1, false, log_lines)
    api.nvim_set_option_value("modifiable", false, { scope = "local", buf = buf })

    api.nvim_set_current_buf(buf)
  end)
end

return M

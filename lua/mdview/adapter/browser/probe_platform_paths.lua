---@module 'mdview.adapter.browser.probe_platform_paths'
-- Provides platform-specific candidate paths for browser executables.
-- Minimal and conservative probe list for Windows, macOS, and Linux.

---@return string[] # List of full paths to browser executables for the current platform.
return function()
  local fn = vim.fn
  local paths = {} ---@type string[]

  if fn.has("win32") == 1 then
    -- Built up with table.insert (not a `{ os.getenv(...), ... }` literal)
    -- because a middle env var can be nil: ipairs() stops at the first hole,
    -- which would silently drop every later base (e.g. LOCALAPPDATA, where
    -- per-user Chrome installs live) whenever PROGRAMFILES(X86) is unset --
    -- as it commonly is under Git Bash/MSYS2, which doesn't pass through
    -- Windows env var names containing parentheses.
    local env_vars = { "PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA" }
    local program_files = {}
    for _, var in ipairs(env_vars) do
      local val = os.getenv(var)
      if val then
        table.insert(program_files, val)
      end
    end
    for _, base in ipairs(program_files) do
      table.insert(paths, base .. "\\Google\\Chrome\\Application\\chrome.exe")
      table.insert(paths, base .. "\\Chromium\\Application\\chrome.exe")
      table.insert(paths, base .. "\\Microsoft\\Edge\\Application\\msedge.exe")
    end
  elseif fn.has("mac") == 1 then
    table.insert(paths, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    table.insert(paths, "/Applications/Chromium.app/Contents/MacOS/Chromium")
    table.insert(paths, "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge")
    table.insert(paths, "/Applications/Firefox.app/Contents/MacOS/firefox")
  else
    -- Assume Linux / Unix-like
    table.insert(paths, "/usr/bin/google-chrome")
    table.insert(paths, "/usr/bin/google-chrome-stable")
    table.insert(paths, "/usr/bin/chromium-browser")
    table.insert(paths, "/usr/bin/chromium")
    table.insert(paths, "/usr/bin/microsoft-edge")
    table.insert(paths, "/usr/bin/microsoft-edge-stable")
    table.insert(paths, "/usr/bin/firefox")
  end

  return paths
end

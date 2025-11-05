---@module 'mdview.adapter.browser.probe_platform_paths'
-- Provides platform-specific candidate paths for browser executables.
-- Minimal and conservative probe list for Windows, macOS, and Linux.

---@return string[] # List of full paths to browser executables for the current platform.
return function ()
  local fn = vim.fn
  local paths = {} ---@type string[]

  if fn.has("win32") == 1 then
    local program_files = { os.getenv("PROGRAMFILES"), os.getenv("PROGRAMFILES(X86)"), os.getenv("LOCALAPPDATA") }
    for _, base in ipairs(program_files) do
      if base and base ~= vim.NIL then
        table.insert(paths, base .. "\\Google\\Chrome\\Application\\chrome.exe")
        table.insert(paths, base .. "\\Chromium\\Application\\chrome.exe")
        table.insert(paths, base .. "\\Microsoft\\Edge\\Application\\msedge.exe")
      end
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
    table.insert(paths, "/usr/bin/msedge")
    table.insert(paths, "/usr/bin/firefox")
  end

  return paths
end


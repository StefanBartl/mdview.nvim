---@module 'mdview.helper.get_exec'
-- Map common command names to their Windows equivalents where appropriate.
-- Example: "npm" -> "npm.cmd" on Windows so uv.spawn can execute the file directly.

local is_windows = require("mdview.helper.is_windows")

---@param cmd string
---@return string|nil
return function (cmd)
	if not cmd then
		return nil
	end
	if is_windows() and cmd == "npm" then
		return "npm.cmd"
	end
	return cmd
end

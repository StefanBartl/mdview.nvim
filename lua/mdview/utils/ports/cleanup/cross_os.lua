---@module 'mdview.utils.ports.cleanup.cross_os'
--- Cross-platform helper to free a TCP port asynchronously and warn about TIME_WAIT states.
--- Usage:
--- kill_port_async(43219)

local M = {}
local uv = vim.loop

--- Kill all processes using a given TCP port asynchronously.
--- @param port number The local TCP port to free
function M.kill_port_async(port)
	if not port or type(port) ~= "number" then
		vim.notify("kill_port_async: invalid port", vim.log.levels.ERROR)
		return
	end

	---@diagnostic disable-next-line LSP-Problems with uv.
	local os_name = uv.os_uname().sysname or ""

	if os_name:match("Windows") then
		-- Windows: PowerShell async
		local ps_cmd = ([[
$port = %d
$connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
if ($connections) {
    $pids = $connections | Where-Object { $_.OwningProcess -ne 0 } | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($pid in $pids) { try { Stop-Process -Id $pid -Force } catch {} }
}
]]):format(port)

		---@diagnostic disable-next-line LSP-Problems with uv.
		uv.spawn(
			"powershell",
			{ args = { "-NoProfile", "-Command", ps_cmd }, stdio = { nil, nil, nil } },
			function(code, _)
				vim.schedule(function()
					if code == 0 then
						vim.notify(("Port %d freed (Windows)"):format(port), vim.log.levels.INFO)
					else
						vim.notify(("Failed to free port %d (Windows)"):format(port), vim.log.levels.WARN)
					end
				end)
			end
		)
	else
		-- Unix: asynchrones lsof + kill
		---@diagnostic disable-next-line LSP-Problems with uv.
		local stdout = uv.new_pipe(false)
		---@diagnostic disable-next-line LSP-Problems with uv.
		local stderr = uv.new_pipe(false)

		local handle
		---@diagnostic disable-next-line LSP-Problems with uv.
		handle = uv.spawn(
			"lsof",
			{ args = { "-ti", string.format("tcp:%d", port) }, stdio = { nil, stdout, stderr } },
			function(code, _)
				-- cleanup pipes & handle
				stdout:close()
				stderr:close()
				handle:close()

				vim.schedule(function()
					if code == 0 then
						vim.notify(("Port %d freed (Unix)"):format(port), vim.log.levels.INFO)
						vim.notify("Note: TIME_WAIT connections may still exist but are harmless.", vim.log.levels.WARN)
					else
						vim.notify(("No processes found on port %d"):format(port), vim.log.levels.INFO)
					end
				end)
			end
		)

		local output_lines = {}
		stdout:read_start(function(err, data)
			if err then
				return
			end
			if data then
				for line in data:gmatch("[^\r\n]+") do
					table.insert(output_lines, line)
				end
			end
		end)

		stdout:read_stop()

		-- kill collected PIDs
		---@diagnostic disable-next-line LSP-Problems with uv.
		uv.new_timer():start(50, 0, function(timer)
			timer:stop()
			timer:close()
			for _, pid in ipairs(output_lines) do
				---@diagnostic disable-next-line LSP-Problems with uv.
				uv.spawn("kill", { args = { "-9", pid } }, function() end)
			end
		end)
	end
end

M.kill_port_async(43219)

return M

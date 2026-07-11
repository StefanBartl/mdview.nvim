---@module 'mdview.bindings.usrcmds.theme'
-- Registers :MDViewTheme <name> — switch the preview theme at runtime.
--
-- Sets browser.theme in the shared config (so the next browser URL carries the
-- new ?theme=) and, if a session is running, re-opens the preview so the change
-- takes effect immediately. In the "default" open_mode this opens a fresh tab
-- with the new theme (the old tab can't be closed programmatically); in
-- "isolated" mode it reuses the isolated browser. Without a running session it
-- just records the choice for the next :MDViewStart.

local libusercmd = require("lib.nvim.usercmd")
local state = require("mdview.core.state")

local M = {}

-- Base theme names that ship with the client (must match THEME_LOADERS in
-- src/client/main.ts). A "-light" / "-dark" suffix may be appended to pin the
-- color scheme, so validation checks the base name only.
---@type string[]
M.known = { "github", "dark-dimmed", "plain" }

---@param name string
---@return boolean
local function is_known(name)
	local base = name:match("^(.-)-light$") or name:match("^(.-)-dark$") or name
	for _, k in ipairs(M.known) do
		if k == base then
			return true
		end
	end
	return false
end

function M.attach()
	libusercmd.create("MDViewTheme", function(cmdopts)
		local name = cmdopts.args and vim.trim(cmdopts.args) or ""
		if name == "" then
			local current = require("mdview.config.browser").defaults.theme
			vim.notify(
				("[mdview] current theme: %s (known: %s)"):format(tostring(current), table.concat(M.known, ", ")),
				vim.log.levels.INFO
			)
			return
		end

		if not is_known(name) then
			vim.notify(
				("[mdview] unknown theme %q — known: %s (optionally suffixed -light/-dark)"):format(
					name,
					table.concat(M.known, ", ")
				),
				vim.log.levels.WARN
			)
			return
		end

		-- Shared table with mdview.config.defaults.browser, so this is picked up
		-- by launcher.resolve_browser_url on the next open.
		require("mdview.config.browser").defaults.theme = name

		if state.get_server() and state.is_attached() then
			-- Re-open so the new theme applies now. Tab-preview mode has no
			-- browser theme, so only the browser path needs re-opening.
			if not require("mdview.config").defaults.open_preview_tab then
				require("mdview").open()
			end
			vim.notify("[mdview] theme set to " .. name .. " (re-opened preview)", vim.log.levels.INFO)
		else
			vim.notify("[mdview] theme set to " .. name .. " (applies on next :MDViewStart)", vim.log.levels.INFO)
		end
	end, {
		desc = "[mdview] Switch the preview theme (github | dark-dimmed | plain, optionally -light/-dark)",
		nargs = "?",
		complete = function(arglead)
			local out = {}
			for _, k in ipairs(M.known) do
				if k:find(arglead, 1, true) == 1 then
					out[#out + 1] = k
				end
			end
			return out
		end,
	})
end

return M

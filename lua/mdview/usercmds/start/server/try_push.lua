---@module 'mdview.usercmds.start.server.try_push'
--- Aggressive initial-push helper with multiple attempts, exponential backoff and optional jitter.
--- Intended to be used when server boot can be slow and user prefers repeated attempts.

local ws_client = require("mdview.adapter.ws_client")
local session = require("mdview.core.session")
local log = require("mdview.helper.log")
local vim = vim

local M = {}

local DEFAULTS = {
	max_attempts = 5,
	initial_delay_ms = 150,
	backoff_factor = 2.0,
	jitter = true,
	wait_timeout_per_attempt_ms = ws_client.WAIT_READY_TIMEOUT or 2000,
}

--- Apply symmetric jitter up to fraction `p` of base (p in 0..1)
--- @param base number
--- @param p number
--- @return number
local function apply_jitter(base, p)
	if not p or p <= 0 then
		return base
	end
	local r = (math.random() * 2 - 1) * p
	return math.max(0, math.floor(base + (base * r)))
end

--- Try to push markdown with retry loop. Non-blocking: returns immediately and schedules attempts.
--- @param path string normalized absolute path
--- @param lines string[] buffer content lines
--- @param opts table|nil { max_attempts?:integer, initial_delay_ms?:integer, backoff_factor?:number, jitter?:boolean, wait_timeout_per_attempt_ms?:integer }
function M.try_push(path, lines, opts)
	if type(path) ~= "string" or type(lines) ~= "table" then
		error("try_push: invalid arguments", 2)
	end

	opts = opts or {}
	local cfg = {
		max_attempts = opts.max_attempts or DEFAULTS.max_attempts,
		initial_delay_ms = opts.initial_delay_ms or DEFAULTS.initial_delay_ms,
		backoff_factor = opts.backoff_factor or DEFAULTS.backoff_factor,
		jitter = (opts.jitter == nil) and DEFAULTS.jitter or opts.jitter,
		wait_timeout_per_attempt_ms = opts.wait_timeout_per_attempt_ms or DEFAULTS.wait_timeout_per_attempt_ms,
	}

	local attempt = 0
	local payload = table.concat(lines, "\n")

	local function attempt_once()
		attempt = attempt + 1
		local delay = math.floor(cfg.initial_delay_ms * (cfg.backoff_factor ^ (attempt - 1)))
		if cfg.jitter then
			delay = apply_jitter(delay, 0.3)
		end

		ws_client.wait_ready(function(ok)
			if ok then
				ws_client.send_markdown(path, payload, { immediate = true })
				session.store(path, lines)
				log.debug(string.format("try_push: success for %s on attempt %d", path, attempt), nil, "try_push", true)
			else
				if attempt < cfg.max_attempts then
					log.debug(
						string.format(
							"try_push: server not ready, scheduling retry %d/%d (delay %dms)",
							attempt,
							cfg.max_attempts,
							delay
						),
						nil,
						"try_push",
						true
					)
					vim.defer_fn(attempt_once, delay)
				else
					log.debug(
						string.format("try_push: failed for %s after %d attempts", path, attempt),
						nil,
						"try_push",
						true
					)
				end
			end
		end, cfg.wait_timeout_per_attempt_ms)
	end

	-- start asynchronous attempts immediately
	vim.defer_fn(attempt_once, 0)
	return true
end

return M

---@module 'mdview.helper.gen_token'
-- Generates a per-session token shared between the spawned mdview-server
-- process and the browser tab it opens, so the relay can reject connections
-- from any other local process or page (DNS-rebinding / stray localhost
-- clients). Not a long-lived credential — regenerated on every server start.

math.randomseed(vim.uv.hrtime())

---@return string
return function()
	local parts = {
		tostring(math.random(0, 0x7fffffff)),
		tostring(math.random(0, 0x7fffffff)),
		tostring(vim.uv.hrtime()),
	}
	return vim.fn.sha256(table.concat(parts, "-"))
end

---@module 'tests.nvim.harness'
-- Tiny test harness for specs that need the real Neovim API (so they can't run
-- under plain busted, which has no `vim`). Provides just enough of busted's
-- surface — describe/it and a luassert-ish assert — to run *_spec.lua files
-- headlessly:
--
--   nvim --headless -u NONE -i NONE --cmd "set rtp+=.,../lib.nvim" \
--     -c "luafile tests/nvim/harness.lua" -c "qa!"
--
-- Discovers tests/nvim/*_spec.lua, runs them, prints a summary, and exits
-- non-zero (via :cq) if anything failed so CI catches it.

local M = { pass = 0, fail = 0, failures = {} }

local function deep_eq(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	local na = 0
	for k, v in pairs(a) do
		na = na + 1
		if not deep_eq(v, b[k]) then
			return false
		end
	end
	local nb = 0
	for _ in pairs(b) do
		nb = nb + 1
	end
	return na == nb
end

local function fmt(v)
	return type(v) == "table" and (vim.inspect(v):gsub("%s+", " ")) or tostring(v)
end

_G.assert = setmetatable({
	are = {
		same = function(e, a)
			if not deep_eq(e, a) then
				error("are.same expected=" .. fmt(e) .. " got=" .. fmt(a), 2)
			end
		end,
		equal = function(e, a)
			if e ~= a then
				error("are.equal expected=" .. fmt(e) .. " got=" .. fmt(a), 2)
			end
		end,
	},
	is_nil = function(a)
		if a ~= nil then
			error("is_nil got=" .. fmt(a), 2)
		end
	end,
	is_true = function(a)
		if a ~= true then
			error("is_true got=" .. fmt(a), 2)
		end
	end,
	is_false = function(a)
		if a ~= false then
			error("is_false got=" .. fmt(a), 2)
		end
	end,
}, {
	__call = function(_, cond, msg)
		if not cond then
			error(msg or "assert failed", 2)
		end
	end,
})

local current = "?"
function _G.describe(name, fn)
	current = name
	fn()
end

function _G.it(name, fn)
	local ok, err = pcall(fn)
	if ok then
		M.pass = M.pass + 1
		print("  ok   [" .. current .. "] " .. name)
	else
		M.fail = M.fail + 1
		M.failures[#M.failures + 1] = current .. " / " .. name .. " -> " .. tostring(err)
		print("  FAIL [" .. current .. "] " .. name .. "  -> " .. tostring(err))
	end
end

-- NB: specs deliberately do NOT call require("mdview").setup() — they require
-- the modules under test and read/patch config defaults directly. setup() runs
-- browser detection and registers user commands, which is both unnecessary here
-- and environment-sensitive (it failed on headless CI runners, cascading into
-- "loop or previous error" module-load failures). Keeping the harness free of
-- it makes the specs pure unit tests of the required modules.

-- Discover and run every tests/nvim/*_spec.lua.
local specs = vim.fn.globpath("tests/nvim", "*_spec.lua", false, true)
table.sort(specs)
for _, spec in ipairs(specs) do
	print("== " .. spec .. " ==")
	local chunk, load_err = loadfile(spec)
	if not chunk then
		M.fail = M.fail + 1
		print("  FAIL could not load " .. spec .. ": " .. tostring(load_err))
	else
		local ok, run_err = pcall(chunk)
		if not ok then
			M.fail = M.fail + 1
			print("  FAIL error running " .. spec .. ": " .. tostring(run_err))
		end
	end
end

print(string.format("\n%d passed, %d failed", M.pass, M.fail))
if M.fail > 0 then
	vim.cmd("cq")
end

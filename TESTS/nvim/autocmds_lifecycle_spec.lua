---@module 'tests.nvim.autocmds_lifecycle_spec'
-- The session's autocommands are attached and torn down as ONE unit. There is
-- no list of autocmd ids kept alongside (the old `autocmds_registry` mirror was
-- retired): the augroup itself is the record. So the properties worth pinning
-- are the ones that list used to guarantee -- stop removes everything, and a
-- second start works -- plus the one it never did: lib's own records go too.

---@diagnostic disable: undefined-global

local autocmds = require("mdview.bindings.autocmds")
local lib_autocmd = require("lib.nvim.bindings.autocmd")
local inbound_poll = require("mdview.adapter.inbound_poll")

local GROUP = "MdviewAutocmds"

-- attach() starts the inbound poller; nothing here needs a live one.
local orig_start, orig_stop = inbound_poll.start, inbound_poll.stop
---@diagnostic disable-next-line: duplicate-set-field
inbound_poll.start = function() end
---@diagnostic disable-next-line: duplicate-set-field
inbound_poll.stop = function() end

---@return integer # how many autocmds Neovim itself still has in the session group
local function native_count()
  local ok, list = pcall(vim.api.nvim_get_autocmds, { group = GROUP })
  return ok and #list or 0
end

describe("session autocmds attach/teardown", function()
  it("attach() registers the session's autocmds in one augroup", function()
    autocmds.teardown() -- clean slate whatever an earlier spec left behind
    autocmds.attach()
    assert.is_true(native_count() > 0)
    assert.is_true(#lib_autocmd.registered({ group = GROUP }) > 0)
  end)

  it("teardown() removes every one of them, natively and from lib's records", function()
    assert.is_true(native_count() > 0)
    autocmds.teardown()
    assert.are.equal(0, native_count())
    assert.are.equal(0, #lib_autocmd.registered({ group = GROUP }))
  end)

  it("teardown() is idempotent", function()
    autocmds.teardown()
    autocmds.teardown()
    assert.are.equal(0, native_count())
  end)

  it("a second attach() after a teardown() registers again (no stale group id)", function()
    autocmds.attach()
    assert.is_true(native_count() > 0)
    autocmds.teardown()
    assert.are.equal(0, native_count())
  end)

  -- restore
  inbound_poll.start, inbound_poll.stop = orig_start, orig_stop
end)

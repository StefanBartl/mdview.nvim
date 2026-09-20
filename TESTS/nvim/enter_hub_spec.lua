---@module 'tests.nvim.enter_hub_spec'
-- The BufEnter hub: three features act on entering a previewable buffer, and
-- they share one autocmd instead of three. What is worth pinning is what each
-- of them used to get from having its own: the pattern filter, the previewable
-- gate, registration order -- and what sharing adds: one normalized path.

---@diagnostic disable: undefined-global

local hub = require("mdview.bindings.autocmds.enter_hub")
local dispatcher = require("lib.nvim.bindings.autocmd.dispatcher")
local normalize = require("mdview.helper.normalize")

local function make_buffer(name, filetype)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
  return buf
end

--- Enter `buf` so BufEnter fires exactly once: switching to it fires the real
--- event by itself, so only a buffer that is already current needs it forced.
local function enter(buf)
  if vim.api.nvim_get_current_buf() == buf then
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
  else
    vim.api.nvim_set_current_buf(buf)
  end
end

describe("enter hub", function()
  hub.reset()
  local md = make_buffer("mdview_spec_hub_A.md", "markdown")
  local other = make_buffer("mdview_spec_hub_B.lua", "lua")
  local scratch = make_buffer("mdview_spec_hub_C.md", "markdown")
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = scratch })

  local calls
  local function reset_calls()
    calls = {}
  end
  local function record(tag)
    return function(ctx)
      calls[#calls + 1] = { tag = tag, buf = ctx.buf, path = ctx.context.path }
    end
  end

  it("runs every registered handler once, in registration order", function()
    reset_calls()
    hub.register("spec.first", { desc = "first", load = record("first") })
    hub.register("spec.second", { desc = "second", load = record("second") })
    enter(md)
    assert.are.equal(2, #calls)
    assert.are.equal("first", calls[1].tag)
    assert.are.equal("second", calls[2].tag)
  end)

  it("hands every handler the same, already normalized path", function()
    reset_calls()
    enter(md)
    local expected = normalize.path(vim.api.nvim_buf_get_name(md))
    assert.are.equal(expected, calls[1].path)
    assert.are.equal(expected, calls[2].path)
    assert.are.equal(md, calls[1].buf)
  end)

  it("never reaches a handler for a buffer outside ft_pattern", function()
    reset_calls()
    enter(other)
    assert.are.equal(0, #calls)
  end)

  it("never reaches a handler for a buffer that matches the pattern but is not previewable", function()
    reset_calls()
    enter(scratch)
    assert.are.equal(0, #calls)
  end)

  it("is listed as one dispatcher with its handlers underneath", function()
    local found
    for _, entry in ipairs(dispatcher.registry()) do
      if entry.name == "mdview_bufenter" and entry.attached then
        found = entry
      end
    end
    assert(found, "mdview_bufenter should be a live, attached dispatcher")
    local owners = {}
    for _, h in ipairs(found.handlers) do
      owners[h.owner] = true
    end
    assert.is_true(owners["spec.first"])
    assert.is_true(owners["spec.second"])
  end)

  it("reset() takes every handler back out", function()
    reset_calls()
    hub.reset()
    enter(other)
    enter(md)
    assert.are.equal(0, #calls)
  end)

  it("reset() is safe to call twice", function()
    hub.reset()
    hub.reset()
  end)

  it("registers and fires again after a reset (the dispatcher is re-attached)", function()
    reset_calls()
    hub.register("spec.again", { desc = "again", load = record("again") })
    enter(other)
    enter(md)
    assert.are.equal(1, #calls)
    assert.are.equal("again", calls[1].tag)
  end)

  -- restore
  hub.reset()
end)

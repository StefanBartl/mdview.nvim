-- TESTS/e2e_session.lua -- a REAL :MDView session, headless: start, switch between
-- markdown buffers, edit, stop, start again.
--
-- Not part of the CI suite (TESTS/nvim/harness.lua): it spawns the installed relay
-- binary, so it needs `:MDView install` to have run once, and it takes a few
-- seconds. It exists for the things the stubbed specs cannot say -- that the
-- BufEnter hub, the live_push autocmds and the teardown work together against a
-- relay that is really there.
--
--   nvim --headless -u NONE -i NONE -c "luafile TESTS/e2e_session.lua" -c "qa!"
--
-- Exits non-zero (`:cq`) on the first failed check. `$LIB_NVIM_PATH` overrides
-- the sibling `../lib.nvim` checkout.
---@diagnostic disable: undefined-global

local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h"))
local lib = vim.env.LIB_NVIM_PATH or (root .. "/../lib.nvim")
vim.opt.rtp:append(root)
vim.opt.rtp:append(vim.fs.normalize(lib))
vim.cmd("filetype plugin on") -- `-u NONE` leaves detection off, and nothing is previewable without a filetype
vim.cmd("runtime plugin/mdview.lua")

local failures = {}
local function check(cond, msg)
  print((cond and "  ok   " or "  FAIL ") .. msg)
  if not cond then
    failures[#failures + 1] = msg
  end
end

local function finish()
  if #failures > 0 then
    print(("\n%d check(s) failed"):format(#failures))
    vim.cmd("cquit 1")
  end
  print("\nMDVIEW_E2E_OK")
end

local ok, err = pcall(function()
  require("mdview").setup({ browser = { browser_autostart = false } })

  local state = require("mdview.core.state")
  local session = require("mdview.core.session")
  local ws = require("mdview.adapter.ws_client")
  local normalize = require("mdview.helper.normalize")
  local dispatcher = require("lib.nvim.bindings.autocmd.dispatcher")
  require("mdview.config.browser").defaults.behavior = "reuse"

  -- Record what is pushed to the relay, and let the real call through.
  local sent = {}
  local real_send = ws.send_content
  ws.send_content = function(key, lines, opts)
    sent[#sent + 1] = { key = key, n = #lines, full = opts and opts.full or false }
    return real_send(key, lines, opts)
  end

  local function hub_owners()
    for _, e in ipairs(dispatcher.registry()) do
      if e.name == "mdview_bufenter" and e.attached then
        local out = {}
        for _, h in ipairs(e.handlers) do
          out[#out + 1] = h.owner
        end
        table.sort(out)
        return table.concat(out, ",")
      end
    end
    return ""
  end

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local A, B = dir .. "/a.md", dir .. "/b.md"
  vim.fn.writefile({ "# A", "text a" }, A)
  vim.fn.writefile({ "# B", "text b", "line 3", "line 4" }, B) -- a different length, so a push is attributable

  local function wait(cond, ms)
    return vim.wait(ms or 20000, cond, 100)
  end
  local function edit(path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end

  for round = 1, 2 do
    print(("round %d"):format(round))
    edit(A)
    vim.cmd("MDView start")
    check(
      wait(function()
        return state.get_server() ~= nil and state.is_attached()
      end, 30000),
      "the session comes up"
    )
    check(
      hub_owners() == "mdview.breadcrumbs,mdview.bufenter,mdview.buffer_switch",
      "the BufEnter hub carries its three handlers"
    )

    -- What a real session has once a browser tab is open: a room to follow.
    state.set_preview_key(normalize.path(A))
    sent = {}
    edit(B)
    wait(function()
      return #sent > 0
    end, 30000)
    vim.wait(2000, function()
      return false
    end) -- let anything else settle
    local full_push
    for _, e in ipairs(sent) do
      if e.full and e.n == 4 then
        full_push = e
      end
    end
    check(full_push ~= nil, "switching A -> B pushes B's whole content (4 lines) to the open tab's room")
    check(full_push and full_push.key == normalize.path(A), "... into the room the tab watches, not B's own")
    check(session.get(normalize.path(B)) ~= nil, "the BufEnter snapshot for B is stored")

    edit(A)
    sent = {}
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# A", "text a", "more" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    check(
      wait(function()
        return #sent > 0
      end, 5000),
      "an edit is live-pushed (a plain autocmd, unchanged)"
    )

    vim.cmd("MDView stop")
    check(
      wait(function()
        return not state.get_server()
      end, 10000),
      "stop shuts the relay down"
    )
    check(not state.is_attached(), "stop clears the attached flag")
    check(hub_owners() == "", "stop detaches the BufEnter hub")
    check(not pcall(vim.api.nvim_get_autocmds, { group = "MdviewAutocmds" }), "stop removes the session augroup")
    vim.cmd("silent! %bwipeout!")
  end
end)

if not ok then
  print("  FAIL unexpected error: " .. tostring(err))
  failures[#failures + 1] = tostring(err)
end
finish()

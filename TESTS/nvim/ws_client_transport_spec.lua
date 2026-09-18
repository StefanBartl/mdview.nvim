---@module 'tests.nvim.ws_client_transport_spec'
-- Verifies the transport-level failure paths of mdview.adapter.ws_client that
-- need no relay: what happens when curl is missing. Before the fix both the
-- health poll and the POST fell back to a shell string (`sh -c "curl ..."`)
-- whose exit status was never read, so a missing curl was reported as a
-- SUCCESSFUL request -- wait_ready marked a dead relay ready and the pending
-- queue dropped the buffer content as "sent". The POST fallback also fed the
-- buffer text through a shell.
--
-- vim.fn.executable / vim.fn.system / vim.fn.jobstart are Neovim globals, so
-- they are stubbed directly (same pattern as health_spec.lua); vim.api.nvim_echo
-- is stubbed to capture the user-facing message instead of printing it.

---@diagnostic disable: undefined-global, duplicate-set-field

-- A private instance: line_diff_transport_spec.lua replaces ws.send_markdown
-- on the shared module for the rest of the run, and this spec needs the real
-- one. The shared instance is put back so nothing else notices.
local shared = package.loaded["mdview.adapter.ws_client"]
package.loaded["mdview.adapter.ws_client"] = nil
local ws = require("mdview.adapter.ws_client")
package.loaded["mdview.adapter.ws_client"] = shared

--- Run `fn` with curl reported as missing and every subprocess entry point
--- armed to fail the test if reached.
---@param fn fun(echoed: string[])
local function without_curl(fn)
  local orig_executable, orig_system, orig_jobstart, orig_echo =
    vim.fn.executable, vim.fn.system, vim.fn.jobstart, vim.api.nvim_echo
  local echoed = {}
  vim.fn.executable = function(name)
    if name == "curl" then
      return 0
    end
    return orig_executable(name)
  end
  vim.fn.system = function()
    error("vim.fn.system must not be reached without curl")
  end
  vim.fn.jobstart = function()
    error("vim.fn.jobstart must not be reached without curl")
  end
  vim.api.nvim_echo = function(chunks)
    for _, chunk in ipairs(chunks) do
      echoed[#echoed + 1] = chunk[1]
    end
  end

  local ok, err = pcall(fn, echoed)

  vim.fn.executable, vim.fn.system, vim.fn.jobstart, vim.api.nvim_echo =
    orig_executable, orig_system, orig_jobstart, orig_echo
  if not ok then
    error(err, 0)
  end
end

describe("ws_client.wait_ready without curl", function()
  it("fails at once with cb(false) instead of reporting the relay ready", function()
    without_curl(function(echoed)
      ws.reset_ready()
      local result = "not called"
      ws.wait_ready(function(ok)
        result = ok
      end, 100)

      assert.is_false(result)
      assert.is_false(ws._ready)
      assert(
        #echoed > 0 and echoed[1]:find("curl not found", 1, true),
        "expected the missing-curl message to be echoed"
      )
    end)
  end)
end)

describe("ws_client.send_markdown without curl", function()
  it("reports the missing curl as a failed POST and never touches a shell", function()
    without_curl(function(echoed)
      ws.send_markdown("C:/spec/no-curl.md", "$(rm -rf ~) `id`", { immediate = true })
      -- the failure notice is scheduled, not echoed inline
      vim.wait(200, function()
        return #echoed > 0
      end)
      assert(#echoed > 0, "expected a failure message")
      assert(echoed[1]:find("curl not found", 1, true), "expected the missing-curl reason, got: " .. echoed[1])
    end)
  end)
end)

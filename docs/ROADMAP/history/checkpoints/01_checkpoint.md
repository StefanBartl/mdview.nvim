> ⚠️ **OUTDATED (pre-rewrite).** A test checkpoint from the Node era:
> it references the `/render` endpoint (now `/update`), the Vite dev port
> 43220 as the preview source and markdown-it rendering. The current health/
> smoke procedure: `curl http://localhost:43219/health` and `:checkhealth mdview`.
> History only. **Current tasks: [`../../ROADMAP.md`](../../ROADMAP.md).**

---

# Checkpoint 1

## Table of content

  - [Checklist + targeted actions](#checklist--targeted-actions)
  - [The behaviour we want](#the-behaviour-we-want)
  - [Test instructions, step by step](#test-instructions-step-by-step)
  - [Notes / edge cases](#notes--edge-cases)
    - [The behaviour we want](#the-behaviour-we-want-1)
    - [Test instructions, step by step](#test-instructions-step-by-step-1)
    - [Notes / edge cases](#notes--edge-cases-1)
    - [The behaviour we want](#the-behaviour-we-want-2)
    - [Test instructions, step by step](#test-instructions-step-by-step-2)
    - [Notes / edge cases](#notes--edge-cases-2)

---

## Checklist + targeted actions

1. Quickly check whether the server + client are reachable

* Server health:

```
curl -sS http://localhost:43219/health
# Expected: ok
```

* Check the server index (returns HTML / the client bootstrap):

```
curl -sS http://localhost:43219/ | sed -n '1,40p'
```

* Check the Vite dev client (the usual dev setup uses port 43220):

```
curl -sS http://localhost:43220/ | sed -n '1,40p'
```

If `http://localhost:43219/` only shows "mdview loading…", that means: the HTML client was loaded, but the browser client has no WS connection or is waiting for content (or the dev client has to be opened on port 43220).

1. Why do you see "mdview loading…" in the browser?
2. The client HTML initially shows only a placeholder (`<div id="mdview-root">mdview loading…</div>`).
3. The browser then loads the JS (Vite dev or the bundled `dist`) and opens a WebSocket connection to `/ws`. Only once the client is connected does it receive `render_update` messages and show rendered HTML.
4. If no browser tab is open or the browser is not connected, you keep seeing only "loading…".

3. Quick test: a manual render POST (this already works — from your output)

```
curl -sS -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "# Hello"
# Expected: JSON with html
```

If the JSON comes back, the server renders correctly. If nothing shows in the browser, it is the client/WS connection or a wrong URL in the browser.

4. Opening the browser automatically: two strategies
* Simple: always open `http://localhost:<server_port>` (already implemented, but perhaps not ideal in a dev setup).
* Better for the dev setup: prefer opening the client URL (the Vite dev server) if reachable (typically 43220). Fall back to the server URL if no dev client is running.

5. Quick commands in Neovim to open the browser manually

* macOS:

```
:lua vim.fn.jobstart({"open", "http://localhost:43219"})
```

* Linux:

```
:lua vim.fn.jobstart({"xdg-open", "http://localhost:43219"})
```

* Windows (cmd):

```
:lua vim.fn.jobstart({"cmd", "/c", "start", "", "http://localhost:43219"})
```

6. A small, safe user command: add `MDViewOpen` (just the small snippet, comments in English, EmmyLua not required here):

```lua
-- add to lua/mdview/usercommands.lua or plugin file
vim.api.nvim_create_user_command("MDViewOpen", function()
  local port = require("mdview.config").defaults.server_port or vim.g.mdview_server_port or 43219
  local server_url = "http://localhost:" .. tostring(port)
  -- prefer vite dev client if reachable
  local dev_port = 43220
  local function try_open(url)
    if vim.fn.has("win32") == 1 then
      vim.fn.jobstart({ "cmd", "/c", "start", "", url })
    elseif vim.fn.has("mac") == 1 then
      vim.fn.jobstart({ "open", url })
    else
      vim.fn.jobstart({ "xdg-open", url })
    end
  end
  -- quick probe of dev client
  local ok = (vim.fn.systemlist("curl -sS -I http://localhost:43220/ | head -n 1 2>/dev/null") ~= "")
  if ok then
    try_open("http://localhost:43220/")
  else
    try_open(server_url)
  end
end, { desc = "[mdview] Open preview in browser (tries vite dev then server)" })
```

7. Automatic open-on-start: the better variant (add the following small piece to `M.start()` in `lua/mdview/init.lua`; it probes the Vite dev port 43220 first, then the server on 43219):

```lua
-- after session.init() and events.attach()
local function probe_and_open(urls)
  for _, u in ipairs(urls) do
    -- quick non-blocking probe using curl; returns exit code 0 on success
    local cmd = { "sh", "-c", "curl -sS -I " .. u .. " >/dev/null 2>&1 && echo ok || echo no" }
    local ok = pcall(vim.fn.system, table.concat(cmd, " "))
    -- fallback simple: just attempt open if curl not available
    if ok then
      local res = vim.fn.system(table.concat(cmd, " "))
      if res:match("ok") then
        -- open and stop
        if vim.fn.has("win32") == 1 then
          vim.fn.jobstart({ "cmd", "/c", "start", "", u })
        elseif vim.fn.has("mac") == 1 then
          vim.fn.jobstart({ "open", u })
        else
          vim.fn.jobstart({ "xdg-open", u })
        end
        return true
      end
    end
  end
  -- fallthrough: try opening first URL anyway
  if vim.fn.has("win32") == 1 then
    vim.fn.jobstart({ "cmd", "/c", "start", "", urls[1] })
  elseif vim.fn.has("mac") == 1 then
    vim.fn.jobstart({ "open", urls[1] })
  else
    vim.fn.jobstart({ "xdg-open", urls[1] })
  end
  return true
end

-- example call: prefer vite then server
local server_port = M.config.server_port or vim.g.mdview_server_port or 43219
local server_url = string.format("http://localhost:%d", server_port)
local vite_url = "http://localhost:43220/"
vim.defer_fn(function() probe_and_open({ vite_url, server_url }) end, 1000)
```

Note: the `sh -c` probe is platform-dependent; on Windows an alternative handling (a PowerShell or cmd test) has to be built in. If the port probe is too complicated, simply calling `open(server_url)` without a probe is fine.

8. Why the browser possibly did not come up automatically for you

* The logs show `EADDRINUSE` and then a nodemon restart — during the first start attempt the port was occupied and nodemon restarted; possibly `wait_ready()` ran before nodemon had finally restarted. `wait_ready()` polls /health; the timeout may need bridging. Fix: raise the `wait_ready()` timeout (e.g. to 10 s) or only open after a successful "server running" log line.
* The dev client (Vite) may not be running — if you open the server URL, the client JS may point at the Vite dev URL, so the client does not work. Hence the prefer-Vite-URL probe makes sense.

9. How to confirm that the browser client sees live updates

* Open the browser manually on the chosen URL (see above).
* In Neovim: change the markdown, save (`:w`). Watch the browser; if the WS connection is active, the content should update automatically.
* In the logs: the `mdview` server log shows broadcasts, or in the mdview client console (browser DevTools -> Console) you see WS open / messages.

10. If nothing helps — debugging aid:

* Set debug=true in `lua/mdview/config.lua` and open `:MDViewShowLogs`.
* Set `vim.g.mdview_server_port` for a custom port.
* Check whether the Vite dev server is running: look for a `vite` process or test `curl http://localhost:43220/`.

Summary (concretely, what to do now):
* `curl http://localhost:43219/health` -> ok (it is)
* `curl http://localhost:43219/` -> check the HTML (shows the client bootstrap)
* If Vite dev is present, open `http://localhost:43220/` instead of the server URL.
* Create a quick `:MDViewOpen` command (code above) — so you can open a tab manually.
* If automatic open-on-start is wanted: patch `M.start()` as above, and raise the `wait_ready` timeout if the nodemon restart is problematic.

## The behaviour we want

1. `:MDViewStart` starts the server silently.
2. As soon as the server is ready, a browser tab opens (once) on the server URL.
3. The currently open markdown buffer is sent to the server once (the initial render), and again on every `BufWritePost`.

The necessary changes are minimal:
* add a small, cross-platform `open_browser(url)` routine that `start()` calls once when the server is ready;
* make sure `send_current_buffer()` runs after `wait_ready()` (that is already wired up).

---

## Test instructions, step by step

1. In Neovim, open a markdown buffer with `:edit TESTS/test.md`.
2. Run `:MDViewStart`.
   * Expectation: `mdview: started` in :messages.
   * The browser should open a tab on `http://localhost:43219` (within a few seconds).
3. If no browser appears:
   * Check whether `curl http://localhost:43219/health` returns `ok`. If not, look at `:MDViewShowLogs` (or `:messages`) for errors.
   * Run `curl -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "$(cat TESTS/test.md)"` manually in a terminal — it should return JSON with `html`.
4. In Neovim: `:w` (save) in the markdown buffer → the server should broadcast the updated HTML to the clients via `POST /render`; the browser client (if connected) shows the update.

---

## Notes / edge cases

* Dev workflow: if the client dev server (Vite) runs separately, you could open the dev client URL (`http://localhost:43220`) instead of `http://localhost:43219` — that is optional and depends on the setup. For prod/distribution `http://localhost:<server_port>` is correct. If you use Vite, the behaviour can be configured via `mdview.config` (e.g. `open_url`).
* If `start` runs on a headless server (e.g. WSL without a GUI), `open_browser` fails silently; you can set `vim.env.MDVIEW_OPEN_CMD` (e.g. `"/mnt/c/Windows/System32/cmd.exe /c start"`), or use `debug = true` and check the logs.
* `ws_client.wait_ready()` uses `/health` polling; that makes sure the initial POST only happens once the HTTP server responds — nevertheless `send_markdown()` enqueues messages and retries if necessary.

---




### The behaviour we want

1. `:MDViewStart` starts the server silently.
2. As soon as the server is ready, a browser tab opens (once) on the server URL.
3. The currently open markdown buffer is sent to the server once (the initial render), and again on every `BufWritePost`.

The necessary changes are minimal:
* add a small, cross-platform `open_browser(url)` routine that `start()` calls once when the server is ready;
* make sure `send_current_buffer()` runs after `wait_ready()` (that is already wired up).

---

### Test instructions, step by step

1. In Neovim, open a markdown buffer with `:edit TESTS/test.md`.
2. Run `:MDViewStart`.
   * Expectation: `mdview: started` in :messages.
   * The browser should open a tab on `http://localhost:43219` (within a few seconds).
3. If no browser appears:
   * Check whether `curl http://localhost:43219/health` returns `ok`. If not, look at `:MDViewShowLogs` (or `:messages`) for errors.
   * Run `curl -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "$(cat TESTS/test.md)"` manually in a terminal — it should return JSON with `html`.
4. In Neovim: `:w` (save) in the markdown buffer → the server should broadcast the updated HTML to the clients via `POST /render`; the browser client (if connected) shows the update.

---

### Notes / edge cases

* Dev workflow: if the client dev server (Vite) runs separately, you could open the dev client URL (`http://localhost:43220`) instead of `http://localhost:43219` — that is optional and depends on the setup. For prod/distribution `http://localhost:<server_port>` is correct. If you use Vite, the behaviour can be configured via `mdview.config` (e.g. `open_url`).
* If `start` runs on a headless server (e.g. WSL without a GUI), `open_browser` fails silently; you can set `vim.env.MDVIEW_OPEN_CMD` (e.g. `"/mnt/c/Windows/System32/cmd.exe /c start"`), or use `debug = true` and check the logs.
* `ws_client.wait_ready()` uses `/health` polling; that makes sure the initial POST only happens once the HTTP server responds — nevertheless `send_markdown()` enqueues messages and retries if necessary.

---


### The behaviour we want

1. `:MDViewStart` starts the server silently.
2. As soon as the server is ready, a browser tab opens (once) on the server URL.
3. The currently open markdown buffer is sent to the server once (the initial render), and again on every `BufWritePost`.

The necessary changes are minimal:
* add a small, cross-platform `open_browser(url)` routine that `start()` calls once when the server is ready;
* make sure `send_current_buffer()` runs after `wait_ready()` (that is already wired up).

---

### Test instructions, step by step

1. In Neovim, open a markdown buffer with `:edit TESTS/test.md`.
2. Run `:MDViewStart`.
   * Expectation: `mdview: started` in :messages.
   * The browser should open a tab on `http://localhost:43219` (within a few seconds).
3. If no browser appears:
   * Check whether `curl http://localhost:43219/health` returns `ok`. If not, look at `:MDViewShowLogs` (or `:messages`) for errors.
   * Run `curl -X POST "http://localhost:43219/render?key=test" -H "Content-Type: text/markdown" --data-binary "$(cat TESTS/test.md)"` manually in a terminal — it should return JSON with `html`.
4. In Neovim: `:w` (save) in the markdown buffer → the server should broadcast the updated HTML to the clients via `POST /render`; the browser client (if connected) shows the update.

---

### Notes / edge cases

* Dev workflow: if the client dev server (Vite) runs separately, you could open the dev client URL (`http://localhost:43220`) instead of `http://localhost:43219` — that is optional and depends on the setup. For prod/distribution `http://localhost:<server_port>` is correct. If you use Vite, the behaviour can be configured via `mdview.config` (e.g. `open_url`).
* If `start` runs on a headless server (e.g. WSL without a GUI), `open_browser` fails silently; you can set `vim.env.MDVIEW_OPEN_CMD` (e.g. `"/mnt/c/Windows/System32/cmd.exe /c start"`), or use `debug = true` and check the logs.
* `ws_client.wait_ready()` uses `/health` polling; that makes sure the initial POST only happens once the HTTP server responds — nevertheless `send_markdown()` enqueues messages and retries if necessary.

---

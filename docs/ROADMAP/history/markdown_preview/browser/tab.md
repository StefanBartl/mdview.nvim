# Overview: the markdown-preview.nvim approach, briefly explained

## Table of content

  - [Detailed components and flow](#detailed-components-and-flow)
  - [Why markdown-preview is designed this way — design reasons](#why-markdown-preview-is-designed-this-way--design-reasons)
  - [Comparison: the markdown-preview approach vs. process/profile-based opening (your approach)](#comparison-the-markdown-preview-approach-vs-processprofile-based-opening-your-approach)
  - [Pros and cons of both strategies — decision criteria](#pros-and-cons-of-both-strategies--decision-criteria)
  - [Practical recommendations / a hybrid strategy](#practical-recommendations--a-hybrid-strategy)
  - [Example: a minimal client handler (browser side)](#example-a-minimal-client-handler-browser-side)
  - [Conclusion (short): which method to choose?](#conclusion-short-which-method-to-choose)

---

markdown-preview.nvim implements a server-side architecture with WebSocket/socket clients (in the browser). On start it opens a locally running HTTP/WebSocket server. To open a preview page the server generates a URL (e.g. `http://localhost:PORT/page/BUFNr`) and hands that URL to the Neovim side, which in turn either:

* calls a configured Vim function (`g:mkdp_browserfunc`), or
* uses a configured browser program (`g:mkdp_browser`), or
* uses the default mechanism to open the URL in the system browser.

In parallel the server maintains a `clients` map per buffer ID; every client connection (browser tab) registers with the server. The server sends events to these clients as needed, e.g. `refresh_content`, `change_bufnr` or `close_page`. The client code (JavaScript in the preview page) reacts to those events — e.g. it runs `window.close()` when a `close_page` event arrives.

This architecture separates opening/controlling (Neovim/server) strictly from the actual tab-closing logic (which lives in the browser client and is cooperative).

---

## Detailed components and flow

* The server generates the URL and manages the clients:

  * `clients[bufnr]` is a list of client objects for that buffer.
  * Every client has a state (e.g. `connected`) and a way to receive events (`emit`).
* Open logic in the server:

  * Checks whether "combine preview" is enabled; it can switch existing clients to a new buffer (emitting `change_bufnr`) instead of opening new tabs.
  * Detects `mkdp_browserfunc`: if set, the server calls that Vim function and passes the URL (giving the user/plugin full control).
  * Otherwise it uses `mkdp_browser` (a string) or the default; internally it calls `openUrl(url, browser?)`.
* Close logic:

  * `closePage({ bufnr })` sends a `close_page` event to all connected clients for that buffer and removes their entries.
  * `closeAllPages()` sends `close_page` to all clients and clears the map.
* Client side (browser):

  * Must handle `close_page` (e.g. `window.close()`) so that the page closes itself.
  * Can contain additional logic (e.g. polling, reconnect, UI hints).

---

## Why markdown-preview is designed this way — design reasons

1. Cooperative control: browsers normally allow a tab only to close itself. By having the plugin send a `close_page` event, the tab performs the close action itself (as browsers require).
2. Flexibility in opening: `mkdp_browserfunc` lets users use arbitrary opening strategies (e.g. system-specific launchers, special flags or browser plugins).
3. Combinability: `combine_preview` allows a "single page, multiple buffers" behaviour — more efficient for the user.
4. Platform independence: the server/client pattern avoids process-management bugs on different operating systems; it relies on standard browser APIs in the client.
5. Security and side effects: no need to create browser profiles or new processes that affect the user's profile.

---

## Comparison: the markdown-preview approach vs. process/profile-based opening (your approach)

| Topic                     |                                     markdown-preview.nvim (server + client events) | Process/profile-based opening (e.g. spawn with a temp profile)                                            |
| ------------------------- | ---------------------------------------------------------------------------------: | --------------------------------------------------------------------------------------------------------- |
| Who closes the tab?       |       The browser client closes itself on the `close_page` event (cooperatively). | Neovim/the plugin terminates the external browser process (proactively), because it controls the started instance. |
| Permissions needed        |                       None special; it uses normal browser functionality. | It must start/stop processes and create temporary profiles; OS-specific paths/flags are needed.            |
| Reliability of closing    | Reliable if the client implements the event correctly; works independently of the OS. | Reliable at terminating the started process instance; but it cannot affect other browser tabs. |
| Complexity                |      Simpler integration: the server sends events, the client implements the behaviour. | Higher: cross-platform process resolution, temp profile management, cleanup.                               |
| User configuration        |        `mkdp_browserfunc` and `mkdp_browser` offer hooks; the plugin stays flexible. | Must be configurable in the plugin (which browser, flags, cleanup), otherwise it is risky.                 |
| Side effects              |               None; it uses an existing browser instance or the user's preferences. | Potentially disruptive: new profiles, browser flags, possibly several browser processes.                   |
| Edge cases                |  The user has JS disabled or the client is not connected → `close_page` has no effect. | The browser can run in the system scope; jobstop may miss the right process group.                   |

---

## Pros and cons of both strategies — decision criteria

* If the goal is to be as benign and compatible as possible (no temporary profiles, no new processes), the **server + client event** approach is recommended. It is lightweight, platform-independent and respects the user's browser policies.
* If the goal is absolute control over opening/closing (e.g. a guaranteed close without client cooperation), the **process-based** route (an own profile / app mode / job tracking) is worth considering — but with higher implementation and maintenance cost and platform pitfalls.

---

## Practical recommendations / a hybrid strategy

1. Primarily: implement server-side `open` + `close_page` events and make sure the client HTML/JS handles `close_page` reliably (including fallbacks). That covers most cases and is minimally invasive.
2. As an extension: optionally offer a process-based opening strategy (configurable by the user) that uses temporary profiles / app mode and stores the created process handle — useful for users who explicitly want Neovim to terminate the instance.
3. Configuration API: expose two options, e.g. `open_strategy = "client"` (default) or `"process"`, plus `browser_executable` / `browserfunc` / `stop_closes_browser` flags.
4. Documentation: explain the implications of both modes clearly (privacy, side effects, platform caveats).
5. Fallback: if `close_page` has no effect (the client is not connected), do not automatically attempt a hard process kill on the system browser — that could close unrelated tabs. Do so only on explicit user configuration.

---

## Example: a minimal client handler (browser side)

```html
<script>
  // Client listens for server events via socket.io / ws and handles close_page.
  socket.on('close_page', () => {
    // Browser allows window.close() only for windows opened by script OR same origin.
    try {
      window.close();
    } catch (e) {
      // fallback: show message asking user to close tab
      console.warn('Preview closed on server; please close this tab.');
    }
  });
</script>
```

This client code is the precondition for `close_page` actually closing the tab.

---

## Conclusion (short): which method to choose?

* For the majority of plugins the **server + client events** approach (as in markdown-preview.nvim) is the best choice: robust, platform-independent, respectful of the user's profile.
* For cases in which the plugin needs a **deterministic, programmatic guarantee** of closing a separate browser instance (e.g. isolated app windows), the **process-based** model with a temporary profile is an option — as long as the plugin configuration makes the risks and platform differences transparent.

---

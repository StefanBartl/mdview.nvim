# Wishlist / features (architecture proposals)

> **A brainstorming/source document.** The consolidated, current task list is in
> [`../../ROADMAP.md`](../../ROADMAP.md); finished items including their rationale
> are in [`../../DONE.md`](../../DONE.md). Some proposals here date from before
> the Go/Rust rewrite and name old endpoints (e.g. `/render?key=`) that no longer
> exist — as ideas they remain valid, but the implementation follows today's
> architecture (Go relay + Rust/WASM client).

1. MDViewStart with file arguments
   * `:MDViewStart /path/to/file.md` could be allowed; the launcher/initial_push then calls an initial `render?key=<normalized>` or starts a targeted push action.
   * API: `nvim_create_user_command("MDViewStart", fn, { nargs = "?", complete = "file" })`.

1. Behaviour on a buffer switch (update vs. new tab vs. no update)
   * Configuration options (already present): `browser_behavior = "reuse" | "new_tab" | "manual"`.
   * Implementation: on a buffer change, `live_push` decides whether it runs `push_buffer` and additionally whether the `launcher` uses the browser handle to open a new URL (new tab) or only `ws_client.send_markdown` for the existing preview.

3. Click-to-navigate (links/anchors in the browser navigate to other files)
   Three possible implementations, with pros and cons:

   * A) The server serves the filesystem (static file serving) and the client rewrites links to `/render?key=normalized_path`.
     * Advantage: simple, the server needs only read access in the CWD.
     * Disadvantage: possible security aspects (only serve below the project root), possibly many files.

    * B) On a link click the client sends a WebSocket message to the Neovim extension/daemon, which then loads the file and pushes it via `/render?key=...`.
         * Advantage: no additional file server needed, Neovim stays the single source of truth.
         * Disadvantage: needs a bidirectional protocol between client ↔ Neovim (the WS to the server already exists, but a server → Neovim bridge has to be implemented or the runner extended).

    * C) Combined: the server knows the workspace root and serves `/file?path=...` restricted to the cwd. The client clicks a link -> fetches `/file?path=...` -> the server reads the file and responds with markdown or redirects to `/render?key=...`.
         * Recommendation: B or C are the most flexible; C is simpler if the server is already started in the project CWD.

---

## Security and UX notes

* For server-side serving: the permitted root can be restricted (project root only), and path normalisation used to avoid directory traversal.
* For automatically opening new browser tabs: a user option can be offered, since many users want only one tab.

---

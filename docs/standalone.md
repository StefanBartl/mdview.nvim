# Background & standalone previews

Normally a preview lives and dies with your Neovim instance: `:MDView start`
spawns the relay as a child process, and `:qa` takes it with you. That's the
right default — but sometimes you want a preview that *stays*.

Three ways to get one, in increasing distance from Neovim:

| | Preview survives `:qa` | Live *unsaved* buffer | Scroll sync / cursor marker | Costs |
|---|---|---|---|---|
| `:MDView start` | ✗ | ✓ | ✓ | nothing extra |
| `:MDView detach` | ✓ | ✓ | ✓ | a second (minimal) nvim |
| `:MDView standalone` | ✓ | ✗ (file on disk) | ✗ | one small relay process |

The rule of thumb: **`detach` when you still want mdview's editor features,
`standalone` when you just want the document rendered.**

---

## `:MDView detach` — a preview that outlives this instance

```vim
:MDView detach                     " current buffer
:MDView detach docs/spec.md        " a specific file
:MDView detach notes.md --no-browser
```

Starts a second Neovim — headless, detached, loading **only** mdview.nvim and
lib.nvim via [`scripts/minimal_init.lua`](../scripts/minimal_init.lua) — and
runs the normal `:MDView start` in it. Because a real Neovim is driving it, you
keep everything: live push on every keystroke, scroll sync, cursor marker,
click-to-navigate.

**When you'd use it**

- *Closing the editor, keeping the doc.* You're done editing the README but want
  it open in a browser tab while you work elsewhere.
- *Isolating a flaky preview.* If something in your own config interferes with
  mdview, `detach` gives you a preview with none of it loaded — also the fastest
  way to answer "is this mdview's bug or my config's?".
- *One long-lived reference doc.* Detach your notes once, then restart Neovim as
  often as you like.

The detached instance quits itself when the preview session ends (it hooks the
`User MDViewSessionEnded` event), so closing the preview tab is the normal way
to stop it. `stop_on_browser_exit` is on by default there for the same reason.

---

## `:MDView standalone` — no Neovim in the chain at all

```vim
:MDView standalone                 " current buffer's file
:MDView standalone README.md
:MDView standalone README.md --no-browser
```

Hands the file to the relay binary's own watch mode and steps out entirely. The
relay polls the file on disk (~4×/s) and pushes changes straight to the browser
— same WebSocket, same in-browser WASM renderer, same sanitization. The only
thing missing is everything that requires knowing where a cursor is.

> **It previews the file on disk.** Unsaved buffer changes don't appear until you
> `:write`. mdview warns you if you run it on a modified buffer.

**When you'd use it**

- *A reference doc beside your work.* API notes, a spec, a cheat sheet — open it
  once, and it keeps following the file no matter what you do to your editor.
- *Rendering something you're not editing in Neovim.* A file another tool
  generates, or a doc a colleague is editing.
- *The cheapest possible always-on preview.* One ~10 MB process, no Neovim.

Runs on `server_port + 100` (43319 by default), deliberately clear of both the
relay port and the Vite dev port, so it can sit alongside a normal session.

With `--no-browser`, mdview prints the preview URL in the notification — that's
the only way to get it, since a detached process's output goes nowhere.

### Requires a relay with `--watch` (v0.3.0+)

Standalone mode needs a relay binary built with watch support. If the one
`install.version` pinned is older, `:MDView standalone` says so and stops rather
than spawning a process that dies silently. To use a locally built relay:

```lua
require("mdview").setup({
  standalone = { binary_path = "~/repos/mdview.nvim/native/server/mdview-server" },
})
```

---

## From the terminal, without opening Neovim first

```sh
scripts/mdview-bg.sh README.md               # preview, return the prompt
scripts/mdview-bg.sh --no-browser notes.md   # relay only
scripts/mdview-bg.sh --fg docs/spec.md       # foreground, Ctrl-C to stop
```

```powershell
.\scripts\mdview-bg.ps1 README.md
.\scripts\mdview-bg.ps1 -NoBrowser notes.md
```

Same thing `:MDView detach` does, entered from a shell: headless Neovim against
the minimal init, detached from the terminal. Symlink it onto your `PATH` and
`mdview-bg some.md` becomes a general-purpose "render this Markdown" command.

> `nvim +MDView --background file.md` is **not** valid Neovim syntax — `+cmd`
> takes no trailing flags. These scripts are the supported spelling of that idea.

Environment: `MDVIEW_PATH` (mdview.nvim checkout, derived from the script by
default), `LIB_NVIM_PATH` (if lib.nvim isn't next to it), `NVIM` (binary to use).

The relay binary can also be driven directly, with no Neovim anywhere:

```sh
mdview-server --watch README.md --web-root <client-bundle-dir>
```

---

## Serverless: `:MDView preview-tab`

Worth naming here since it answers a related question — a preview with **no
server, no browser, and no network** at all:

```vim
:MDView preview-tab
```

Renders the buffer as a read-only Treesitter-highlighted mirror in a Neovim tab.
No relay, no WebSocket, no WASM. It's not a full preview (no CSS, no themes, no
rendered tables) — it's for a quick structural read when you don't want a browser
in the loop, or on a machine with no GUI.

---

## Choosing, in one paragraph

Editing the document right now? Plain `:MDView start`. Want that same preview to
survive closing the editor? `:MDView detach`. Only want the rendered document
and don't care about cursor-following? `:MDView standalone` — it's the smallest
and the most robust. No browser available at all? `:MDView preview-tab`.

See also: [commands.md](commands.md) for the full command reference,
[architecture.md](architecture.md) for how the relay and renderer fit together.

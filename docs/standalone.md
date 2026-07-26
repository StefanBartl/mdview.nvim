# Background & standalone previews

Normally a preview lives and dies with your Neovim instance: `:MDView start`
spawns the relay as a child process, and `:qa` takes it with you. That's the
right default — but sometimes you want a preview that *stays*.

`:MDView standalone` gives you one, with no Neovim in the chain at all.

| | Preview survives `:qa` | Live *unsaved* buffer | Scroll sync / cursor marker |
|---|---|---|---|
| `:MDView start` | ✗ | ✓ | ✓ |
| `:MDView standalone` | ✓ | ✗ (file on disk) | ✗ |

The rule of thumb: **`start` while you're editing the document, `standalone`
when you just want it rendered and kept open.**

---

## `:MDView standalone` — no Neovim in the chain

```vim
:MDView standalone                 " current buffer's file
:MDView standalone README.md
:MDView standalone README.md --no-browser
```

Hands the file to the relay binary's own watch mode and steps out entirely. The
relay polls the file on disk (~4×/s) and pushes changes straight to the browser
— same WebSocket, same in-browser WASM renderer, same sanitization. The only
things missing are the ones that require knowing where a cursor is.

> **It previews the file on disk.** Unsaved buffer changes don't appear until you
> `:write`. mdview warns you if you run it on a modified buffer.

**When you'd use it**

- *A reference doc beside your work.* API notes, a spec, a cheat sheet — open it
  once, and it keeps following the file no matter what you do to your editor.
- *Rendering something you're not editing in Neovim.* A file another tool
  generates, or a doc a colleague is editing.
- *The cheapest possible always-on preview.* One small process, no Neovim, and
  it can't be taken down by anything happening in your editor.

Runs on `server_port + 100` (43319 by default), deliberately clear of both the
relay port and the Vite dev port, so it can sit alongside a normal session.

With `--no-browser`, mdview prints the preview URL in the notification — that's
how you open it yourself, or from another device on the same machine.

### Requires a relay with `--watch` (v0.3.0+)

Standalone mode needs a relay binary built with watch support. If the one
`install.version` pinned is older, `:MDView standalone` says so and stops rather
than spawning a process that dies silently. To use a locally built relay until a
release ships:

```lua
require("mdview").setup({
  standalone = { binary_path = "~/repos/mdview.nvim/native/server/mdview-server" },
})
```

---

## From the terminal, without opening Neovim first

```sh
scripts/mdview-bg.sh README.md               # preview in the browser
scripts/mdview-bg.sh --no-browser notes.md   # relay only, prints the URL
```

```powershell
.\scripts\mdview-bg.ps1 README.md
.\scripts\mdview-bg.ps1 -NoBrowser notes.md
```

Runs a throwaway headless Neovim just long enough to fire `:MDView standalone`
— which spawns the relay and detaches it — then quits. The relay keeps running
independently, following the file; nothing stays resident. Symlink a wrapper
onto your `PATH` and `mdview-bg some.md` becomes a general-purpose "render this
Markdown" command.

> `nvim +MDView --background file.md` is **not** valid Neovim syntax — `+cmd`
> takes no trailing flags. These scripts are the supported spelling of that idea.

Environment: `MDVIEW_PATH` (mdview.nvim checkout, derived from the script by
default), `LIB_NVIM_PATH` (if lib.nvim isn't next to it),
`MDVIEW_STANDALONE_BIN` (relay override, same role as `standalone.binary_path`
above), `NVIM` (binary to use).

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

Editing the document right now? Plain `:MDView start`. Want the rendered
document kept open regardless of what happens to your editor — a reference doc
that follows the file? `:MDView standalone`, from inside Neovim or via
`scripts/mdview-bg.*` from a shell. No browser available at all? `:MDView
preview-tab`.

See also: [commands.md](commands.md) for the full command reference,
[architecture.md](architecture.md) for how the relay and renderer fit together.

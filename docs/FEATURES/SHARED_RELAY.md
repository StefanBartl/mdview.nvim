# Shared relay

One relay process and one preview tab for every Neovim instance you have open,
instead of one relay and one tab per instance.

## One preview tab for all Neovim instances

Opt-in (`shared_relay = { enabled = true }`); without it every instance runs
its own relay and its own tab, as before.

- **Attach instead of spawn.** The first `:MDView start` spawns the relay with
  `--shared`, detached from that instance, and the relay writes its port and
  token to `stdpath("state")/mdview/relay.json` (readable by you only). A
  `:MDView start` in another instance reads that file, checks that the relay
  answers (`GET /attach`, a stale file is ignored and replaced) and attaches:
  no second relay, no second tab. The tab already open is taken over.
- **The tab follows the focused instance.** Only the instance that owns the
  tab's room pushes into it; the others stay quiet. An instance takes the tab
  over (with its current Markdown buffer, as a full snapshot) when it gains the
  focus -- `FocusGained`, which needs a terminal with focus reporting (Windows
  Terminal, WezTerm, kitty, Neovide and most others) -- or, as the fallback
  for a terminal without it, on the first activity in it: cursor moved, buffer
  entered, insert mode. An instance whose current buffer is not one mdview
  previews does not take the tab over; it keeps showing the other document.
  The others learn from their heartbeat (every `shared_relay.heartbeat_ms`)
  that they lost the room and stop pushing.
  The spotlight.nvim mirror (`browser.spotlight_sync`) goes with the tab: a
  takeover replaces the other instance's spotlights with this one's (or clears
  them), and a background instance does not send its spotlight changes.
- **Write-backs go to the owner of the document on screen.** Checkbox ticks,
  text fields, block edits, click-to-navigate and reverse scroll are queued at
  the relay; each instance names itself when it polls, and gets only the
  requests of the rooms it owns. The instance that pushed last owns the room.
- **The same file in two instances:** the focused one wins. It is the one whose
  text the tab shows, so it is also the one a checkbox tick or a block edit is
  applied to; the other instance's buffer sees the change once the file is
  saved and reloaded there, as with any edit from another instance.
- **Lifetime.** Every request naming an instance is a heartbeat; `:MDView stop`
  and quitting Neovim detach from the relay (they no longer close the tab or
  kill the relay while other instances use it). The relay ends -- and closes
  the tab -- two seconds after the last instance detached, or once no instance
  has been heard from for `shared_relay.idle_timeout_s`. A machine that slept
  does not count as silence.
- **Security.** The relay stays loopback-only and token-gated, as always; the
  shared token lives in the discovery file, written with user-only
  permissions (`0600`, inside the user's own state directory on Windows) and
  removed by the relay when it ends -- only while it still names that relay,
  so an older relay never deletes a newer one's file. Every instance of the
  same user can read it, which is the point; no other user can.
- **Versions.** The relay reports the shared protocol it speaks; an instance
  only attaches to a relay that speaks its own, otherwise it spawns one of its
  own (so two plugin versions never half-work against one relay).
- **Needs a relay with `--shared`** -- newer than the pinned release `v0.4.3`;
  until the next release point `dev.binary_path` at a locally built relay
  (`npm run build:go`).

`:MDView open` still opens a tab for the current buffer of its own (a second
tab, if one is open already); `:MDView start` again in an attached instance
takes the open tab over instead.

- **Module:** `lua/mdview/adapter/shared_relay.lua`, `native/server/shared.go`, `native/server/internal/relay/clients.go`
- **Usercmds:** `:MDView start`, `:MDView stop`
- **Config:** `shared_relay.enabled` (default `false`), `shared_relay.heartbeat_ms` (default `2000`), `shared_relay.idle_timeout_s` (default `30`)

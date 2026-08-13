# Workflow — getting real use out of mdview.nvim day to day

Every feature here is documented on its own elsewhere (`docs/FEATURES/
PREVIEW.md`, `RENDERING.md`, `SECURITY.md`, `OPERATIONS.md`,
`docs/commands.md`). This is the different question: once a session is
running, *how do the pieces actually combine* — which controls apply live
vs. need a restart, which commands answer overlapping-looking questions,
and what breaks first when something's misconfigured.

## Two ways to get a Markdown file on screen, and they don't compose

`:MDView start` is the real thing: relay + WebSocket + WASM render pipeline,
browser tab, full live-preview control set (cursor marker, scroll sync,
zoom, overlays, reveal, breadcrumbs). `:MDView preview-tab` is a
deliberately separate, much cheaper path — a read-only Treesitter-mirrored
buffer in its own Neovim tab, no relay, no browser, no WASM. They run on
independent lifecycles (separate autocommand augroups) and neither implies
the other — except one config knob bridges them: `open_preview_tab = true`
makes `:MDView start` open the tab instead of a browser, while the relay/
WASM pipeline keeps running underneath, so `:MDView open` can still bring
up the browser later without restarting anything. If a live-preview control
command (`:MDView cursor …`, `:MDView zoom …`) seems to do nothing, check
which of the two you're actually looking at — none of the live-preview
controls touch the plain `preview-tab` mirror.

## Config changes vs. live control pushes — most `:MDView` subcommands do both

`cursor`, `zoom`, `overlay`, `reveal`, `sync`, `theme`, and `blanklines` all
follow the same pattern: they write to the shared config (so the choice
survives into the *next* `:MDView start`/reopened tab via its query string)
and, if a session is currently running, additionally push a live control
update over the relay so the open tab updates without a reload. The
practical consequence: running one of these commands with no session up is
never wasted — `:MDView cursor caret` before you've even started previewing
still takes effect the moment you do. The commands report which case just
happened ("applies on next :MDView start" vs. an immediate confirmation),
which is the fast way to tell whether a change actually landed live.

## Reading logs: pick the layer, not just "the log"

Four different views exist because they cover four different layers, and
reaching for the wrong one wastes the trip:

- **`:MDView log`** — the plugin's own Lua-side ring (launcher, live-push,
  `ws_client`). Start here for "why didn't my keystroke reach the relay".
- **`:MDView weblogs`** — the relay process's stdout, including
  `[client]`-tagged lines forwarded from the browser. Start here for "the
  relay started but the browser tab shows nothing" — that's where a WASM
  init failure or a render error would surface.
- **`:MDView file-log on`** — turns persistent, opt-in disk logging on for
  the *relay* capture above, for a problem that needs reproducing across a
  restart rather than read live.
- **`:MDView breadcrumbs`** — not a debug log at all; a human-facing outline
  of which document/section was visited when, for writing follow-up notes
  after a session, not for diagnosing a bug.

For a bug report that needs handing off whole, skip assembling these by
hand — `:MDView diagnose` writes one file covering config, install status,
and session state together, and opens it immediately.

## `:checkhealth mdview` before assuming a bug — it usually is one of three things

Three failure modes cover most "the preview doesn't work" reports, and
`:checkhealth mdview` distinguishes all three in one pass instead of
guessing: (1) `curl`/`tar` missing, so the first-run download in
`:MDView start` never completed — the health check's "installed assets"
section reports cached-or-not for both the relay binary and the client
bundle, and additionally verifies a *complete* bundle
(`index.html` + a `.wasm` file), since an interrupted extract otherwise
fails silently later as a blank browser tab with no error anywhere; (2)
`lib.nvim` missing or half-installed — a hard dependency, reported as an
error rather than a warning, unlike the optional companions section below
it; (3) a session claims to be running but `GET /health` doesn't return
`ok` — a relay process that's up but wedged, distinct from "no session
running" (which is itself reported as fine, not a warning).

## Security posture is two independent halves — know which one a report is about

`SECURITY.md` and `RENDERING.md` cover different attack surfaces that
happen to both matter for "is this preview safe to run": the relay's
loopback-only bind + per-session token + Origin allowlist stops an
unauthorized process/page from *reaching* the relay at all; the comrak→
ammonia sanitizer stops a *malicious document's own content* (embedded raw
HTML, a crafted code-fence attribute) from ever reaching the DOM
unsanitized, independent of who's allowed to view it. A report like "can a
website read my buffer" is the first half; "can my own Markdown file XSS
the preview" is the second — worth clarifying which one's actually being
asked before chasing the wrong mechanism.

## Zoom is for the viewer, not you — a workflow-shaped reason it exists at all

`:MDView zoom` reads as a cosmetic nicety until the actual use case: a video
call downsamples whatever's shared, so the preview's font at 100% often
isn't legible to whoever's watching your screen, even though it's fine for
you. Bump zoom for the call, `:MDView zoom reset` after — it persists into
the shared config, so it's worth remembering to reset rather than starting
the next session pre-zoomed for no reason.

## Overlays are additive, not exclusive — the TOC doesn't replace breadcrumbs or scroll sync

`:MDView overlay toc on` mounts a floating outline *on top of* whatever
else is active — scroll sync, the cursor marker, reveal state — none of
which it interacts with or disables. It answers "where am I in the whole
document" (structure), where breadcrumbs answers "where have I *been* this
session" (history) and the cursor marker answers "where exactly is my
cursor right now" (position) — three different questions that happen to
render in the same tab, not three settings for the same thing. `:MDView
overlay list` is the fast way to check what's currently mounted before
assuming a missing outline means the feature is broken rather than just off.

## Standalone mode trades interactivity for persistence — know the trade before reaching for it

`:MDView standalone` (or the `mdview-bg` scripts, which just automate
firing that command from a throwaway headless Neovim) is the right call
when the preview needs to outlive the editor session — but it gives up
everything that requires knowing where a cursor is: no scroll sync, no
cursor marker, no unsaved-buffer push (it previews the file *as saved on
disk*, polled ~4×/s). If a preview needs to survive `:qa` **and** track live
cursor position, that combination doesn't exist — standalone and the normal
session are different tools for different moments, not two settings on one
feature. It also needs a relay built with `--watch` support (v0.3.0+) and
probes the binary before starting, so an old cached binary fails fast with
a clear message rather than spawning a process that silently can't do the
job.

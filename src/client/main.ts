// src/client/main.ts
/* Client bootstrapping:
   - Loads the Rust/WASM render+sanitize module
   - Connects to the relay's WebSocket for this document (key/token from the URL)
   - Renders every incoming raw-markdown message through WASM and injects the
     result (already sanitized inside the WASM module) into the DOM
   - Scrolls to follow the cursor position when a scroll-sync ping arrives
     (nvim-to-browser half of bidirectional scrolling; see docs/Roadmap/Roadmap.md)
*/

import { createTransport } from './transport/transportFactory';
import { DiffDoc, isEnvelope } from './render/diffDoc';
import { installClickNav } from './render/clickNav';
import { pickScrollTarget, fractionInBlock, hasSourcepos } from './render/scrollSync';
import { markExternalLinks, parseExternalLinkMode } from './render/externalLinks';
import { updateCursorMarker, parseCursorMarkerMode } from './render/cursorMarker';
import {
  initOverlays,
  setOverlay,
  setOverlays,
  notifyCursor as notifyOverlayCursor,
  notifyRender as notifyOverlayRender,
  dispatchOverlayControl,
} from './render/overlays';
import { installHistory, onDocChange } from './render/history';
import { highlight, parseHighlighter } from './highlight';
import init, { render_markdown } from './wasm-render/mdview_wasm_render.js';

// Available visual themes, each a CSS module under ./themes/. Loaded lazily
// so only the selected one is fetched. Add a theme by dropping a CSS file
// here and a matching Lua config value (see lua/mdview/config/DEFAULTS.lua's
// `render.theme`). The CSS side-effect import applies the stylesheet.
const THEME_LOADERS: Record<string, () => Promise<unknown>> = {
  github: () => import('./themes/github.css'),
  'dark-dimmed': () => import('./themes/dark-dimmed.css'),
  plain: () => import('./themes/plain.css'),
  tokyonight: () => import('./themes/tokyonight.css'),
  catppuccin: () => import('./themes/catppuccin.css'),
};

// Apply the theme named by the ?theme= URL param (default "github"). A
// "-light" / "-dark" suffix pins the color scheme (data-theme on <html>);
// without it, the theme follows the OS prefers-color-scheme.
async function applyTheme(params: URLSearchParams): Promise<void> {
  const requested = params.get('theme') || 'github';
  const suffixed = requested.match(/^(.*)-(light|dark)$/);
  const base = suffixed ? suffixed[1] : requested;
  if (suffixed) {
    document.documentElement.setAttribute('data-theme', suffixed[2]);
  }
  const load = THEME_LOADERS[base] ?? THEME_LOADERS.github;
  try {
    await load();
  } catch (err) {
    console.error('[mdview] failed to load theme', requested, err);
    await THEME_LOADERS.github();
  }
}

// Tags a WS message as a scroll-position ping ("<line>/<total>") rather than
// document content — must match native/server/main.go's scrollMessagePrefix.
// \x01 is a non-printable control byte that can never appear in typed
// Markdown text, so there's no ambiguity with real content.
const SCROLL_MESSAGE_PREFIX = '\x01';

// Tags a WS message as a "close this tab now" signal — must match
// native/server/main.go's closeMessagePrefix. Sent when the session stops so
// preview tabs opened in the OS default browser (which mdview can't close via a
// process handle) close themselves cooperatively.
const CLOSE_MESSAGE_PREFIX = '\x02';

// Tags a WS message as "the previewed document changed to <path>" — must match
// native/server/main.go's docMessagePrefix. Drives browser Back/Forward.
const DOC_MESSAGE_PREFIX = '\x04';

// Tags a WS message as a live preview-control update (small JSON, e.g.
// {"cursor":"caret"} / {"zoom":1.2}) — must match native/server/main.go's
// controlMessagePrefix. Powers :MDViewCursor / :MDViewZoom without a reload.
const CONTROL_MESSAGE_PREFIX = '\x05';

function applyScrollPing(container: HTMLElement, message: string): void {
  // Payload: "line/total/viewfrac[/col]". viewfrac (0..1) is where in the browser
  // viewport the cursor line should sit — Neovim sends a small value for "top"
  // mode or its own cursor-in-window fraction for "cursor" (mirror) mode. The
  // optional trailing col (0-based byte) is used by the cursor caret, not here.
  const parts = message.slice(SCROLL_MESSAGE_PREFIX.length).split('/');
  const line = Number(parts[0]);
  const total = Number(parts[1]);
  const viewfrac = Number(parts[2]);
  if (!Number.isFinite(line)) return;

  const target = pickScrollTarget(container, line);
  if (!target) {
    if (!hasSourcepos(container) && Number.isFinite(total) && total > 0) {
      // Fallback for a renderer without sourcepos: proportional estimate.
      const ratio = Math.min(1, Math.max(0, (line - 1) / total));
      container.scrollTop = ratio * (container.scrollHeight - container.clientHeight);
    } else {
      container.scrollTop = 0; // cursor is before the first block
    }
    return;
  }

  // Line-accurate position: the block's top in content coordinates plus the
  // cursor's interpolated fraction through the block's line span; then place
  // that at `viewfrac` of the viewport.
  const rect = target.el.getBoundingClientRect();
  const contRect = container.getBoundingClientRect();
  const blockTopInContent = rect.top - contRect.top + container.scrollTop;
  const targetY = blockTopInContent + fractionInBlock(target, line) * rect.height;
  const vf = Number.isFinite(viewfrac) ? Math.min(1, Math.max(0, viewfrac)) : 0;
  container.scrollTop = targetY - vf * container.clientHeight;
}

async function boot() {
  const params = new URLSearchParams(window.location.search);

  // Theme is purely cosmetic — load it fire-and-forget so a slow/failing
  // stylesheet fetch can never block the WASM init or the WebSocket
  // connection (which is what actually renders the document). Awaiting it
  // here previously meant a hung theme import left the page stuck on
  // "mdview loading…" forever.
  void applyTheme(params);

  await init();

  const key = params.get('key');
  const token = params.get('token');

  // Report browser-side diagnostics back to the relay (which prints them to
  // stdout, captured into :MDViewShowWebLogs / :MDViewDiagnose) so problems
  // in the page are visible from Neovim without opening devtools. Best-effort
  // and token-gated; a no-op if key/token are missing.
  const clientLog = (msg: string): void => {
    if (!token) return;
    try {
      void fetch(`/clientlog?token=${encodeURIComponent(token)}`, {
        method: 'POST',
        body: msg,
        keepalive: true,
      });
    } catch {
      /* diagnostics must never throw */
    }
  };

  if (!key || !token) {
    console.error('[mdview] missing key/token in URL; refusing to connect');
    clientLog('missing key/token in URL; refusing to connect');
    return;
  }

  clientLog(`boot: connecting (key=${key}, theme=${params.get('theme') || 'github'})`);

  const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
  const url = `${scheme}://${location.host}/ws?key=${encodeURIComponent(key)}&token=${encodeURIComponent(token)}`;

  // Opt-in WebTransport (HTTP/3). The Lua side adds ?transport=webtransport
  // only when experimental.webtransport is enabled; the factory feature-detects
  // and falls back to WebSocket on any failure, so this never breaks the
  // preview. The WebTransport URL points at an https /wt endpoint (backend is a
  // documented future step — see docs/Roadmap/WebTransportAPI/DESIGN.md).
  const preferWebTransport = params.get('transport') === 'webtransport';
  const webTransportUrl = `https://${location.host}/wt?key=${encodeURIComponent(key)}&token=${encodeURIComponent(token)}`;
  const webTransportCertHash = params.get('wtcerthash') || undefined;

  let transport;
  try {
    transport = await createTransport(url, {
      preferWebTransport,
      webTransportUrl,
      webTransportCertHash,
      log: clientLog,
    });
  } catch (err) {
    console.error('[mdview] transport failed', err);
    clientLog(`transport failed: ${String(err)}`);
    return;
  }
  clientLog('websocket connected');

  const container = document.getElementById('mdview-root');
  let firstRender = true;

  // Code-fence highlighter chosen per session (?hl= from browser.highlighter).
  // The implementation is lazy-imported inside highlight(), so an unselected
  // highlighter is never loaded.
  const highlighter = parseHighlighter(params.get('hl'));

  // How external links behave (?extlinks= from browser.external_links).
  const externalLinkMode = parseExternalLinkMode(params.get('extlinks'));

  // Neovim cursor marker (?cursor= from browser.cursor_marker). Track the last
  // cursor line/column so the marker can be re-placed after a re-render too.
  // "caret" mode needs the inline source-position spans from the WASM renderer,
  // so it renders with the source map on; "line"/"off" render without it. Both
  // are mutable so :MDViewCursor can change them live (see the control channel).
  let cursorMarkerMode = parseCursorMarkerMode(params.get('cursor'));
  let wantSourceMap = cursorMarkerMode === 'caret';
  let lastCursorLine = -1;
  let lastCursorCol = -1;

  // Preserve runs of consecutive blank lines as vertical space instead of
  // collapsing them (?blanklines=1 from browser.preserve_blank_lines). Mutable
  // so :MDViewBlanklines can flip it live (see the control channel).
  let preserveBlanks = params.get('blanklines') === '1';

  // Overlays (?overlays=a,b from browser.overlays; :MDViewOverlay toggles them
  // live). Independent, toggleable layers drawn over the document — see
  // docs/Roadmap/KONZEPT_overlays.md.
  if (container) {
    initOverlays(container);
    for (const name of (params.get('overlays') ?? '').split(',')) {
      const n = name.trim();
      if (n) setOverlay(n, true);
    }
  }

  // Preview zoom (?zoom= from browser.zoom; :MDViewZoom updates it live). Scales
  // #mdview-root's font-size; the stylesheet sizes everything in em, so the whole
  // document scales proportionally.
  const applyZoom = (factor: number): void => {
    if (!container || !Number.isFinite(factor) || factor <= 0) return;
    container.style.fontSize = `${16 * factor}px`;
  };
  {
    const z = Number(params.get('zoom'));
    if (Number.isFinite(z) && z > 0 && z !== 1) applyZoom(z);
  }

  // Show/hide a small "scroll sync paused" badge (:MDViewSync). Created lazily
  // and toggled by presence so it costs nothing until first used.
  let syncBadge: HTMLElement | null = null;
  const setSyncPausedBadge = (paused: boolean): void => {
    if (paused) {
      if (!syncBadge) {
        syncBadge = document.createElement('div');
        syncBadge.className = 'mdview-sync-badge';
        syncBadge.setAttribute('aria-hidden', 'true');
        syncBadge.textContent = '⏸ scroll sync paused';
        document.body.appendChild(syncBadge);
      }
    } else if (syncBadge) {
      syncBadge.remove();
      syncBadge = null;
    }
  };

  // POST a document path to Neovim's /nav bridge (used by click-to-navigate and
  // by Back/Forward). Neovim resolves relative paths against the source doc and
  // opens absolute paths directly.
  const navigateTo = (target: string): void => {
    try {
      void fetch(`/nav?token=${encodeURIComponent(token)}&key=${encodeURIComponent(key)}`, {
        method: 'POST',
        body: target,
        keepalive: true,
      });
    } catch {
      /* navigation is best-effort */
    }
  };

  // Opt-in click-to-navigate: hand relative-link clicks to Neovim via /nav
  // (the Lua side adds ?nav=1 when experimental.click_navigate is on). Neovim
  // opens the target document, which flows back into this tab via the push path.
  if (container && params.get('nav') === '1') {
    installClickNav(container, (target: string) => {
      clientLog(`nav: ${target}`);
      navigateTo(target);
    });
  }

  // Browser Back/Forward: Neovim announces the current document (\x04 ping) so
  // we can maintain history; on popstate we ask Neovim to reopen the target.
  // The reopen goes through /nav, so it needs the inbound poller (click_navigate,
  // on by default) to be running.
  installHistory({ navigateTo: (abs: string) => navigateTo(abs) });

  // Click-to-reveal for private blocks (```private renders to [data-private],
  // blurred by default). Clicking one reveals/re-hides it; :MDViewReveal toggles
  // all at once (see applyControl).
  if (container) {
    container.addEventListener('click', (ev) => {
      const el = (ev.target as HTMLElement | null)?.closest?.('[data-private]') as HTMLElement | null;
      if (el && container.contains(el)) el.toggleAttribute('data-revealed');
    });
  }

  // Opt-in reverse scroll (browser -> Neovim). While applying an incoming
  // nvim->browser scroll ping we set scrollSuppressUntil so the resulting
  // 'scroll' event doesn't bounce back to Neovim and create a feedback loop.
  let scrollSuppressUntil = 0;
  const SCROLL_SUPPRESS_MS = 250;
  if (container && params.get('rscroll') === '1') {
    // Visible hint that reverse scroll is on, so a viewer knows they may scroll
    // the preview themselves (otherwise it's an invisible capability).
    const badge = document.createElement('div');
    badge.className = 'mdview-rscroll-badge';
    badge.setAttribute('aria-hidden', 'true');
    badge.textContent = '⇅ scroll enabled';
    document.body.appendChild(badge);

    let lastSent = 0;
    container.addEventListener('scroll', () => {
      const now = Date.now();
      if (now < scrollSuppressUntil) return; // caused by an incoming ping
      if (now - lastSent < 120) return; // throttle
      lastSent = now;
      const max = container.scrollHeight - container.clientHeight;
      const ratio = max > 0 ? container.scrollTop / max : 0;
      try {
        void fetch(`/scrollback?token=${encodeURIComponent(token)}&key=${encodeURIComponent(key)}`, {
          method: 'POST',
          body: String(ratio),
          keepalive: true,
        });
      } catch {
        /* reverse scroll is best-effort */
      }
    });
  }

  // Reassembles full text from the opt-in line-diff transport's envelopes. When
  // line_diff is off, no \x03 envelopes arrive and this stays unused.
  const doc = new DiffDoc();

  // Last rendered markdown, so a live control update (e.g. switching cursor mode
  // to/from "caret", which needs source-map spans) can re-render without waiting
  // for the next push from Neovim.
  let lastText = '';

  // Render markdown text through the WASM module (output already sanitized
  // inside WASM — safe to assign to innerHTML) into the preview container.
  const renderMarkdown = (text: string): void => {
    if (!container) return;
    lastText = text;
    try {
      container.innerHTML = render_markdown(text, wantSourceMap, preserveBlanks);
      // Make external links open in a new tab so a click doesn't navigate the
      // preview away (default; see browser.external_links).
      markExternalLinks(container, externalLinkMode);
      // Highlight fenced code after the sanitized HTML is in the DOM. Fire and
      // forget (the highlighter is async for Shiki) — it only adds/replaces
      // markup on the trusted, already-rendered DOM and never throws.
      void highlight(highlighter, container);
      // innerHTML above wiped the cursor marker element; re-place it.
      if (lastCursorLine >= 0) {
        updateCursorMarker(container, lastCursorLine, lastCursorCol >= 0 ? lastCursorCol : null, cursorMarkerMode);
      }
      // Overlays derive from the document (headings, positions) — let them
      // refresh against the new content.
      notifyOverlayRender();
      if (firstRender) {
        firstRender = false;
        clientLog(`first render ok (${text.length} bytes)`);
      }
    } catch (err) {
      console.error('[mdview] render failed', err);
      clientLog(`render failed: ${String(err)}`);
    }
  };

  // Apply a live control update (:MDViewCursor / :MDViewZoom). Best-effort: a
  // malformed payload is ignored rather than breaking the preview.
  const applyControl = (json: string): void => {
    let msg: {
      cursor?: unknown;
      zoom?: unknown;
      reveal?: unknown;
      overlay?: unknown;
      overlays?: unknown;
      overlayData?: unknown;
      sync?: unknown;
      blanklines?: unknown;
    };
    try {
      msg = JSON.parse(json) as typeof msg;
    } catch {
      return;
    }
    // Overlay toggles: a single {name, on} or a batch {name: bool, …}.
    if (msg.overlay && typeof msg.overlay === 'object') {
      const o = msg.overlay as { name?: unknown; on?: unknown };
      if (typeof o.name === 'string' && typeof o.on === 'boolean') setOverlay(o.name, o.on);
    }
    if (msg.overlays && typeof msg.overlays === 'object') {
      setOverlays(msg.overlays as Record<string, boolean>);
    }
    // Overlay-addressed payload: {overlayData: {name, data}}.
    if (msg.overlayData && typeof msg.overlayData === 'object') {
      const d = msg.overlayData as { name?: unknown; data?: unknown };
      if (typeof d.name === 'string') dispatchOverlayControl(d.name, d.data);
    }
    if (typeof msg.reveal === 'boolean' && container) {
      // Reveal/hide all private blocks at once (:MDViewReveal).
      container.classList.toggle('mdview-reveal-all', msg.reveal);
    }
    if (typeof msg.cursor === 'string') {
      const mode = parseCursorMarkerMode(msg.cursor);
      cursorMarkerMode = mode;
      const needSourceMap = mode === 'caret';
      if (needSourceMap !== wantSourceMap) {
        // Toggling caret changes whether the renderer must emit source-position
        // spans, so re-render the current document with the new setting.
        wantSourceMap = needSourceMap;
        if (container) renderMarkdown(lastText);
      } else if (container) {
        updateCursorMarker(
          container,
          lastCursorLine,
          lastCursorCol >= 0 ? lastCursorCol : null,
          cursorMarkerMode,
        );
      }
    }
    if (typeof msg.zoom === 'number') {
      applyZoom(msg.zoom);
    }
    if (typeof msg.sync === 'string') {
      // :MDViewSync pause/resume — show a "sync paused" badge so a viewer knows
      // the preview is intentionally frozen while you look something up in
      // Neovim (the preview simply stops receiving scroll pings while paused).
      setSyncPausedBadge(msg.sync === 'paused');
    }
    if (typeof msg.blanklines === 'boolean') {
      // :MDViewBlanklines — toggling blank-line preservation changes the render
      // output, so re-render the current document with the new setting.
      if (msg.blanklines !== preserveBlanks) {
        preserveBlanks = msg.blanklines;
        if (container) renderMarkdown(lastText);
      }
    }
  };

  transport.onMessage((rawMessage: string) => {
    if (rawMessage.startsWith(CLOSE_MESSAGE_PREFIX)) {
      // Session stopped — close this tab. window.close() only works for
      // script-opened windows in some browsers; if it's blocked, show a note
      // so the tab isn't left silently stale.
      clientLog('close signal received; closing tab');
      window.close();
      if (container) {
        container.innerHTML =
          '<p style="opacity:.6">mdview session stopped — you can close this tab.</p>';
      }
      return;
    }

    if (rawMessage.startsWith(DOC_MESSAGE_PREFIX)) {
      onDocChange(rawMessage.slice(DOC_MESSAGE_PREFIX.length));
      return;
    }

    if (rawMessage.startsWith(CONTROL_MESSAGE_PREFIX)) {
      applyControl(rawMessage.slice(CONTROL_MESSAGE_PREFIX.length));
      return;
    }

    if (!container) return;

    if (rawMessage.startsWith(SCROLL_MESSAGE_PREFIX)) {
      applyScrollPing(container, rawMessage);
      // The same ping carries the cursor line (and column) — update the marker.
      const fields = rawMessage.slice(SCROLL_MESSAGE_PREFIX.length).split('/');
      const cursorLine = Number(fields[0]);
      const cursorCol = Number(fields[3]);
      if (Number.isFinite(cursorLine)) {
        lastCursorLine = cursorLine;
        lastCursorCol = Number.isFinite(cursorCol) ? cursorCol : -1;
        updateCursorMarker(container, cursorLine, lastCursorCol >= 0 ? lastCursorCol : null, cursorMarkerMode);
        notifyOverlayCursor(cursorLine, lastCursorCol >= 0 ? lastCursorCol : 0);
      }
      // The scrollTop we just set fires a 'scroll' event; suppress reverse-scroll
      // sends briefly so it doesn't echo back to Neovim (feedback loop).
      scrollSuppressUntil = Date.now() + SCROLL_SUPPRESS_MS;
      return;
    }

    // Opt-in line-diff transport: \x03-prefixed full/diff envelopes. DiffDoc
    // reassembles the current text; a desynced diff returns null and is skipped
    // (the next full snapshot resyncs), so we only re-render on real changes.
    if (isEnvelope(rawMessage)) {
      const text = doc.apply(rawMessage);
      if (text !== null) renderMarkdown(text);
      return;
    }

    // Default transport: the message IS the full markdown document.
    renderMarkdown(rawMessage);
  });
}

boot().catch(err => console.error('[mdview] boot failed:', err));

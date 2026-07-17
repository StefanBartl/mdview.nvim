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

function applyScrollPing(container: HTMLElement, message: string): void {
  // Payload: "line/total/viewfrac". viewfrac (0..1) is where in the browser
  // viewport the cursor line should sit — Neovim sends a small value for "top"
  // mode or its own cursor-in-window fraction for "cursor" (mirror) mode.
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
  // cursor line so the marker can be re-placed after a re-render too.
  const cursorMarkerMode = parseCursorMarkerMode(params.get('cursor'));
  let lastCursorLine = -1;

  // Opt-in click-to-navigate: hand relative-link clicks to Neovim via /nav
  // (the Lua side adds ?nav=1 when experimental.click_navigate is on). Neovim
  // opens the target document, which flows back into this tab via the push path.
  if (container && params.get('nav') === '1') {
    installClickNav(container, (target: string) => {
      clientLog(`nav: ${target}`);
      try {
        void fetch(`/nav?token=${encodeURIComponent(token)}&key=${encodeURIComponent(key)}`, {
          method: 'POST',
          body: target,
          keepalive: true,
        });
      } catch {
        /* navigation is best-effort */
      }
    });
  }

  // Opt-in reverse scroll (browser -> Neovim). While applying an incoming
  // nvim->browser scroll ping we set scrollSuppressUntil so the resulting
  // 'scroll' event doesn't bounce back to Neovim and create a feedback loop.
  let scrollSuppressUntil = 0;
  const SCROLL_SUPPRESS_MS = 250;
  if (container && params.get('rscroll') === '1') {
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

  // Render markdown text through the WASM module (output already sanitized
  // inside WASM — safe to assign to innerHTML) into the preview container.
  const renderMarkdown = (text: string): void => {
    if (!container) return;
    try {
      container.innerHTML = render_markdown(text);
      // Make external links open in a new tab so a click doesn't navigate the
      // preview away (default; see browser.external_links).
      markExternalLinks(container, externalLinkMode);
      // Highlight fenced code after the sanitized HTML is in the DOM. Fire and
      // forget (the highlighter is async for Shiki) — it only adds/replaces
      // markup on the trusted, already-rendered DOM and never throws.
      void highlight(highlighter, container);
      // innerHTML above wiped the cursor marker element; re-place it.
      if (lastCursorLine >= 0) updateCursorMarker(container, lastCursorLine, cursorMarkerMode);
      if (firstRender) {
        firstRender = false;
        clientLog(`first render ok (${text.length} bytes)`);
      }
    } catch (err) {
      console.error('[mdview] render failed', err);
      clientLog(`render failed: ${String(err)}`);
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

    if (!container) return;

    if (rawMessage.startsWith(SCROLL_MESSAGE_PREFIX)) {
      applyScrollPing(container, rawMessage);
      // The same ping carries the cursor line — update the cursor marker.
      const cursorLine = Number(rawMessage.slice(SCROLL_MESSAGE_PREFIX.length).split('/')[0]);
      if (Number.isFinite(cursorLine)) {
        lastCursorLine = cursorLine;
        updateCursorMarker(container, cursorLine, cursorMarkerMode);
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

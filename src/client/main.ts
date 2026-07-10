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
import init, { render_markdown } from './wasm-render/mdview_wasm_render.js';

// Available visual themes, each a CSS module under ./themes/. Loaded lazily
// so only the selected one is fetched. Add a theme by dropping a CSS file
// here and a matching Lua config value (see lua/mdview/config/DEFAULTS.lua's
// `render.theme`). The CSS side-effect import applies the stylesheet.
const THEME_LOADERS: Record<string, () => Promise<unknown>> = {
  github: () => import('./themes/github.css'),
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

function applyScrollPing(container: HTMLElement, message: string): void {
  const [lineStr, totalStr] = message.slice(SCROLL_MESSAGE_PREFIX.length).split('/');
  const line = Number(lineStr);
  const total = Number(totalStr);
  if (!Number.isFinite(line) || !Number.isFinite(total) || total <= 0) return;

  const ratio = Math.min(1, Math.max(0, (line - 1) / total));
  container.scrollTop = ratio * (container.scrollHeight - container.clientHeight);
}

async function boot() {
  const params = new URLSearchParams(window.location.search);

  await applyTheme(params);
  await init();

  const key = params.get('key');
  const token = params.get('token');

  if (!key || !token) {
    console.error('[mdview] missing key/token in URL; refusing to connect');
    return;
  }

  const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
  const url = `${scheme}://${location.host}/ws?key=${encodeURIComponent(key)}&token=${encodeURIComponent(token)}`;
  const transport = await createTransport(url);

  const container = document.getElementById('mdview-root');

  transport.onMessage((rawMessage: string) => {
    if (!container) return;

    if (rawMessage.startsWith(SCROLL_MESSAGE_PREFIX)) {
      applyScrollPing(container, rawMessage);
      return;
    }

    try {
      // render_markdown returns HTML that has already passed through the
      // sanitizer inside the WASM module — safe to assign directly.
      container.innerHTML = render_markdown(rawMessage);
    } catch (err) {
      console.error('[mdview] render failed', err);
    }
  });
}

boot().catch(err => console.error('[mdview] boot failed:', err));

// src/client/main.ts
/* Client bootstrapping:
   - Loads the Rust/WASM render+sanitize module
   - Connects to the relay's WebSocket for this document (key/token from the URL)
   - Renders every incoming raw-markdown message through WASM and injects the
     result (already sanitized inside the WASM module) into the DOM
*/

import { createTransport } from './transport/transportFactory';
import init, { render_markdown } from './wasm-render/mdview_wasm_render.js';

async function boot() {
  await init();

  const params = new URLSearchParams(window.location.search);
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

  transport.onMessage((rawMarkdown: string) => {
    if (!container) return;
    try {
      // render_markdown returns HTML that has already passed through the
      // sanitizer inside the WASM module — safe to assign directly.
      container.innerHTML = render_markdown(rawMarkdown);
    } catch (err) {
      console.error('[mdview] render failed', err);
    }
  });
}

boot().catch(err => console.error('[mdview] boot failed:', err));

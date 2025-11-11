// ADD: Annotations
// src/client/main.ts
/* Client bootstrapping:
   - Connects to WebSocket on server
   - Receives render updates (html) and injects into container
*/

import { createTransport } from './transport/transportFactory';

async function boot() {
  // const url = `ws://${location.host}/ws`;
	const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
  const url = `${scheme}://${location.host}/ws`; //${location.host}/ws;
  const transport = await createTransport(url);

  transport.onMessage((msg: string) => {
    // handle incoming render_update etc.
    try {
      const parsed = JSON.parse(msg);
      if (parsed.type === 'render_update' && typeof parsed.payload === 'string') {
        const container = document.getElementById('mdview-root');
        if (container) container.innerHTML = parsed.payload;
      }
    } catch (err) {
      console.error('invalid message', err);
    }
  });

  await transport.sendMessage(JSON.stringify({ type: 'hello' }));
}

boot().catch(err => console.error('boot failed:', err));

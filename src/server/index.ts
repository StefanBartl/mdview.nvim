// src/server/index.ts
// Updated: optimize POST /render handling with cache-aware broadcast

import { renderWithCache } from './render.js';
import { MdviewServer } from './mdviewServer.js';

const PORT = Number(process.env.MDVIEW_PORT) || 43219;

(async () => {
  try {
    // Singleton-Server starten
    const server = await MdviewServer.getInstance(PORT);

    console.log(`[mdview-server] Running on http://localhost:${server.getPort()}`);
    console.log(`ws endpoint: ws://localhost:${server.getPort()}/ws`);

    // Minimal HTTP-Listener
    const httpServer = (server as any).server as import('node:http').Server;
    httpServer.on('request', async (req, res) => {
      try {
        if (req.method === 'POST' && req.url?.startsWith('/render')) {
          let body = '';
          req.on('data', chunk => (body += chunk));
          req.on('end', () => {
            const urlObj = new URL(req.url!, `http://localhost`);
            const rawKey = String(urlObj.searchParams.get('key') || `inline-${Date.now()}`);
            const key = rawKey.replace(/\\/g, '/'); // Windows-safe
            const markdown = String(body || '');

            console.log(`[mdview-server] POST /render key=${key} markdown_len=${markdown.length}`);

            // Markdown rendern mit Cache
            const { html, cached } = renderWithCache(key, markdown);

            // Broadcast nur bei Cache-Miss
            if (!cached) {
              const payload = JSON.stringify({ type: 'render_update', payload: html, key, cached });
              server.broadcast(payload);
            }

            // Response an Client
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ html, cached }));
          });
        } else if (req.method === 'GET' && req.url === '/health') {
          res.writeHead(200, { 'Content-Type': 'text/plain' });
          res.end('ok');
        } else {
          res.writeHead(404);
          res.end();
        }
      } catch (err) {
        console.error('[mdview-server] HTTP request error', err);
        // Nur einmalig Fehler senden
        if (!res.headersSent) {
          res.writeHead(500);
          res.end(String(err));
        }
      }
    });
  } catch (err) {
    console.error('[mdview-server] failed to start', err);
  }
})();

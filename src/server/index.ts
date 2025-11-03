/* Minimal server skeleton for development.
   - Provides HTTP static folder for client
   - Provides WebSocket server for live updates
*/

import express from 'express';
import { WebSocketServer } from 'ws';
import path from 'path';

const app = express();
const PORT = Number(process.env.MDVIEW_PORT) || 43219;

app.use('/', express.static(path.join(process.cwd(), 'dist', 'client')));

const server = app.listen(PORT, () => {
  console.log(`mdview server running at http://localhost:${PORT}`);
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
  console.log('client connected');
  ws.on('message', (msg) => {
    console.log('received', msg.toString());
  });
  ws.send(JSON.stringify({ type: 'hello', payload: 'mdview' }));
});

// ADD: Annotations
// src/client/transport/websocket.transport.ts
import type { Transport } from './transport.interface';

export class WebSocketTransport implements Transport {
  private ws!: WebSocket;
  private onMessageCb?: (message: string) => void;
  private url: string;

  constructor(url: string) {
    this.url = url;
  }

  async initialize(): Promise<void> {
    return new Promise((resolve, reject) => {
      const serverPort =
        (window as any).__MDVIEW_SERVER_PORT__ ||
        new URLSearchParams(window.location.search).get('server_port') ||
        43219;

      const ws = new WebSocket(`ws://localhost:${serverPort}/ws`);

      ws.onopen = () => {
        console.log('[mdview] WebSocket connected on port', serverPort);
      };

      ws.onmessage = ev => {
        console.log('[mdview] WS message:', ev.data);
      };

      ws.onerror = ev => {
        console.error('[mdview] WebSocket error', ev);
      };
    });
  }

  async sendMessage(message: string): Promise<void> {
    if (this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(message);
    } else {
      // Wait briefly, then attempt send once
      await new Promise(r => setTimeout(r, 10));
      this.ws.send(message);
    }
  }

  onMessage(cb: (message: string) => void): void {
    this.onMessageCb = cb;
  }

  async close(): Promise<void> {
    this.ws.close();
  }
}

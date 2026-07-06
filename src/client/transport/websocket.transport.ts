// src/client/transport/websocket.transport.ts
import type { Transport } from './transport.interface';

export class WebSocketTransport implements Transport {
  private ws!: WebSocket;
  private onMessageCb?: (message: string) => void;

  constructor(private readonly url: string) {}

  async initialize(): Promise<void> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.url);
      this.ws = ws;

      ws.onopen = () => {
        console.log('[mdview] WebSocket connected:', this.url);
        resolve();
      };

      ws.onmessage = ev => {
        this.onMessageCb?.(String(ev.data));
      };

      ws.onerror = ev => {
        console.error('[mdview] WebSocket error', ev);
        reject(ev);
      };
    });
  }

  async sendMessage(message: string): Promise<void> {
    if (this.ws.readyState === WebSocket.OPEN) {
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

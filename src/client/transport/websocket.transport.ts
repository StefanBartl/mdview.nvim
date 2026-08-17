// src/client/transport/websocket.transport.ts
import type { Transport } from './transport.interface';

/**
 * WebSocket transport with reconnect. The relay may not be listening the instant
 * the tab loads — a freshly built or first-run relay binary can take a few
 * seconds to bind (and mdview now opens the browser without waiting for it) — so
 * the first connection retries with backoff instead of failing the page. After
 * connecting, a dropped socket (relay restart, transient error) reconnects in
 * the background; on rejoin the relay re-sends the room's last payload, so the
 * document reappears without any special resync here.
 */
export class WebSocketTransport implements Transport {
  private ws: WebSocket | null = null;
  private onMessageCb?: (message: string) => void;
  private closed = false;
  private connectedOnce = false;

  // Initial-connect retry: ~200ms * 60 ≈ 12s of relay-startup tolerance, a bit
  // more than the Neovim side's readiness window, before giving up the *first*
  // connection. Reconnects after a successful connect are unbounded but slow.
  private static readonly RETRY_MS = 200;
  private static readonly MAX_INITIAL_ATTEMPTS = 60;
  private static readonly RECONNECT_MS = 1000;

  constructor(private readonly url: string) {}

  async initialize(): Promise<void> {
    return new Promise((resolve, reject) => {
      let attempts = 0;

      const attempt = (): void => {
        if (this.closed) return;
        attempts += 1;
        const ws = new WebSocket(this.url);
        this.ws = ws;

        ws.onopen = () => {
          this.connectedOnce = true;
          console.log('[mdview] WebSocket connected:', this.url);
          resolve();
        };

        ws.onmessage = (ev) => {
          this.onMessageCb?.(String(ev.data));
        };

        ws.onclose = () => {
          if (this.closed) return;
          if (this.connectedOnce) {
            // Lost an established connection — keep trying to get it back.
            setTimeout(attempt, WebSocketTransport.RECONNECT_MS);
          } else if (attempts < WebSocketTransport.MAX_INITIAL_ATTEMPTS) {
            // Relay not up yet — retry the first connection.
            setTimeout(attempt, WebSocketTransport.RETRY_MS);
          } else {
            reject(new Error(`[mdview] could not reach the relay at ${this.url} after ${attempts} attempts`));
          }
        };

        // Let onclose drive retries: a failed connect fires error then close, so
        // handling it in one place avoids double-scheduling.
        ws.onerror = () => {
          if (this.connectedOnce) console.error('[mdview] WebSocket error; will reconnect');
        };
      };

      attempt();
    });
  }

  async sendMessage(message: string): Promise<void> {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(message);
    }
  }

  onMessage(cb: (message: string) => void): void {
    this.onMessageCb = cb;
  }

  async close(): Promise<void> {
    this.closed = true;
    this.ws?.close();
  }
}

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
  // connection. After a successful connect, a dropped socket reconnects with
  // exponential backoff (1s → 2s → … capped at 30s) so a relay that has gone
  // for good (e.g. Neovim quit) doesn't spin the console with a connection
  // attempt every second forever — it settles to a quiet once-every-30s probe.
  private static readonly RETRY_MS = 200;
  private static readonly MAX_INITIAL_ATTEMPTS = 60;
  private static readonly RECONNECT_MIN_MS = 1000;
  private static readonly RECONNECT_MAX_MS = 30000;
  private reconnectDelay = WebSocketTransport.RECONNECT_MIN_MS;

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
          this.reconnectDelay = WebSocketTransport.RECONNECT_MIN_MS; // reset backoff
          console.log('[mdview] WebSocket connected:', this.url);
          resolve();
        };

        ws.onmessage = (ev) => {
          this.onMessageCb?.(String(ev.data));
        };

        ws.onclose = () => {
          if (this.closed) return;
          if (this.connectedOnce) {
            // Lost an established connection — back off, then try to get it back.
            setTimeout(attempt, this.reconnectDelay);
            this.reconnectDelay = Math.min(
              this.reconnectDelay * 2,
              WebSocketTransport.RECONNECT_MAX_MS,
            );
          } else if (attempts < WebSocketTransport.MAX_INITIAL_ATTEMPTS) {
            // Relay not up yet — retry the first connection at a steady pace.
            setTimeout(attempt, WebSocketTransport.RETRY_MS);
          } else {
            reject(new Error(`[mdview] could not reach the relay at ${this.url} after ${attempts} attempts`));
          }
        };

        // onclose drives retries (a failed connect fires error then close), so
        // nothing to do here — and no per-attempt console noise: the browser
        // already logs each failed connection on its own.
        ws.onerror = () => {};
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

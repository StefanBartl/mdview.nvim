// ADD: Annotations
import type { Transport } from "./transport.interface";

export class WebSocketTransport implements Transport {
  private ws!: WebSocket;
  private onMessageCb?: (message: string) => void;
  private url: string;

  constructor(url: string) {
    this.url = url;
  }

  async initialize(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(this.url);
      this.ws.addEventListener("open", () => resolve());
      this.ws.addEventListener("message", (ev) => {
        const data = typeof ev.data === "string" ? ev.data : String(ev.data);
        if (this.onMessageCb) this.onMessageCb(data);
      });
      this.ws.addEventListener("error", (err) => reject(err));
    });
  }

  async sendMessage(message: string): Promise<void> {
    if (this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(message);
    } else {
      // Wait briefly, then attempt send once
      await new Promise((r) => setTimeout(r, 10));
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

// ADD: Annotations
// NOTE: This is a stub/POC skeleton. Real implementation needs HTTP/3 server & TLS.

// src/client/webtransport.transport.ts

// This is a POC adapter for WebTransport. Many WebTransport types are still
// experimental in TypeScript lib definitions; safe casts are used to satisfy LSP.

import type { Transport } from "./transport.interface";

export class WebTransportAdapter implements Transport {
  private session!: any; // use `any` because DOM lib may not include WebTransport yet
  private onMessageCb?: (message: string) => void;
  private url: string;

  constructor(url: string) {
    // convert ws:// -> https:// for WebTransport usage
    this.url = url.replace(/^ws:/, "https:").replace(/^wss:/, "https:");
  }

  async initialize(): Promise<void> {
    // runtime feature-detect
    if (!(window as any).WebTransport) {
      throw new Error("WebTransport not available in this browser");
    }

    // cast to any to avoid LSP errors where typings are missing
    this.session = new (window as any).WebTransport(this.url);
    // session.ready exists on WebTransport API
    if (this.session.ready) await this.session.ready;

    // Read incoming bidirectional streams in a robust way
    // Use explicit type casts because TS lib might not mark incomingBidirectionalStreams
    const incoming = (this.session.incomingBidirectionalStreams as any);
    (async () => {
      // If async iterator is not present, fallback to manual handling (best-effort)
      if (incoming && typeof incoming[Symbol.asyncIterator] === "function") {
        for await (const stream of incoming) {
          await this.handleIncomingStream(stream);
        }
      } else {
        // fallback: no async iterator support in environment — do nothing
      }
    })();
  }

  private async handleIncomingStream(stream: any): Promise<void> {
    try {
      const reader = stream.readable.getReader();
      const chunks: Uint8Array[] = [];
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        // value might be a Uint8Array or ArrayBufferView
        const chunk = value instanceof Uint8Array ? value : new Uint8Array(value);
        chunks.push(chunk);
      }
      const text = new TextDecoder().decode(concat(chunks));
      if (this.onMessageCb) this.onMessageCb(text);
    } catch (e) {
      // swallow stream errors in POC
      console.warn("webtransport handleIncomingStream error", e);
    }
  }

  async sendMessage(message: string): Promise<void> {
    // Use a bidirectional stream for reliability
    const stream = await (this.session.createBidirectionalStream() as Promise<any>);
    const writer = stream.writable.getWriter();
    // write may be async, but writer.close() may be sync in some impls; still await safe
    await writer.write(new TextEncoder().encode(message));
    // close does not necessarily return a useful promise in all impls; await optional
    await (writer.close?.() as Promise<void> | void);
  }

  onMessage(cb: (message: string) => void): void {
    this.onMessageCb = cb;
  }

  sendDatagram(data: Uint8Array): void {
    // Datagrams API may not exist on all implementations; use optional chaining
    try {
      (this.session.datagrams as any)?.send?.(data);
    } catch (e) {
      // ignore datagram failures silently in POC
    }
  }

  async close(): Promise<void> {
    try {
      await (this.session.close as any)();
    } catch {
      // ignore close errors in POC
    }
  }
}

/** helper: concat Uint8Array chunks */
function concat(chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((s, c) => s + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.length;
  }
  return out;
}

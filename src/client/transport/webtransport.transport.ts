// src/client/transport/webtransport.transport.ts
//
// EXPERIMENTAL / opt-in future transport. WebTransport runs over HTTP/3 (QUIC)
// and, unlike WebSocket, requires TLS even on localhost — the relay must serve
// an HTTP/3 endpoint and hand the browser the certificate hash. The Go relay
// does not speak HTTP/3 yet (see docs/Roadmap/WebTransportAPI/DESIGN.md), so
// opting in today feature-detects WebTransport, attempts it, and — because no
// backend answers — cleanly falls back to WebSocket in the factory. This class
// is the client half kept ready so that when the HTTP/3 relay lands, no client
// rewrite is needed.
//
// The wire model mirrors the WebSocket path: a single bidirectional stream
// carrying UTF-8 text frames (the relay pushes raw markdown / scroll pings;
// the client is receive-mostly). Framing is deliberately minimal and may be
// revised alongside the backend.

import type { Transport } from './transport.interface';

/** True when the running browser exposes the WebTransport API. */
export function supportsWebTransport(): boolean {
  return typeof (globalThis as { WebTransport?: unknown }).WebTransport === 'function';
}

// Minimal structural typings for the parts of the WebTransport API we use,
// so this compiles without DOM lib "dom.webtransport" being guaranteed.
interface WTReadableStreamReader {
  read(): Promise<{ value?: Uint8Array; done: boolean }>;
}
interface WTReadableStream {
  getReader(): WTReadableStreamReader;
}
interface WTWritableStreamWriter {
  write(chunk: Uint8Array): Promise<void>;
  close(): Promise<void>;
}
interface WTWritableStream {
  getWriter(): WTWritableStreamWriter;
}
interface WTBidirectionalStream {
  readable: WTReadableStream;
  writable: WTWritableStream;
}
interface WTLike {
  ready: Promise<void>;
  closed: Promise<unknown>;
  createBidirectionalStream(): Promise<WTBidirectionalStream>;
  close(): void;
}
type WTCtor = new (url: string, opts?: unknown) => WTLike;

export class WebTransportTransport implements Transport {
  private wt?: WTLike;
  private writer?: WTWritableStreamWriter;
  private onMessageCb?: (message: string) => void;
  private closed = false;

  constructor(private readonly url: string) {}

  async initialize(): Promise<void> {
    const Ctor = (globalThis as { WebTransport?: WTCtor }).WebTransport;
    if (!Ctor) {
      throw new Error('WebTransport is not supported in this browser');
    }
    const wt = new Ctor(this.url);
    this.wt = wt;
    await wt.ready;

    const stream = await wt.createBidirectionalStream();
    this.writer = stream.writable.getWriter();
    // Read loop runs detached; errors end it and let the factory's caller
    // notice a dead transport via a closed promise if it awaits one.
    void this.readLoop(stream.readable.getReader());
  }

  private async readLoop(reader: WTReadableStreamReader): Promise<void> {
    const decoder = new TextDecoder();
    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        if (value && this.onMessageCb) {
          this.onMessageCb(decoder.decode(value, { stream: true }));
        }
      }
    } catch {
      /* stream ended / errored — nothing to do, transport is done */
    }
  }

  async sendMessage(message: string): Promise<void> {
    if (this.closed || !this.writer) return;
    await this.writer.write(new TextEncoder().encode(message));
  }

  onMessage(cb: (message: string) => void): void {
    this.onMessageCb = cb;
  }

  async close(): Promise<void> {
    this.closed = true;
    try {
      await this.writer?.close();
    } catch {
      /* best effort */
    }
    this.wt?.close();
  }
}

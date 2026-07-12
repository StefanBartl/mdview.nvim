// src/client/transport/webtransport.transport.ts
//
// WebTransport (HTTP/3) transport. Pairs with the Go relay's /wt endpoint
// (opt-in experimental.webtransport). The relay serves a short-lived
// self-signed cert; the browser trusts it via serverCertificateHashes (the
// hex SHA-256 passed in the URL as ?wtcerthash=). Each server->client message
// arrives on its own unidirectional stream, so a fully-read stream IS one
// message — no framing needed. On any failure the factory falls back to
// WebSocket, so this never breaks the preview.

import type { Transport } from './transport.interface';

/** True when the running browser exposes the WebTransport API. */
export function supportsWebTransport(): boolean {
  return typeof (globalThis as { WebTransport?: unknown }).WebTransport === 'function';
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.trim();
  const bytes = new Uint8Array(Math.floor(clean.length / 2));
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.substr(i * 2, 2), 16);
  }
  return bytes;
}

interface WTStreamReader {
  read(): Promise<{ value?: Uint8Array; done: boolean }>;
}
interface WTReadable {
  getReader(): WTStreamReader;
}
interface WTIncomingStreamsReader {
  read(): Promise<{ value?: WTReadable; done: boolean }>;
}
interface WTLike {
  ready: Promise<void>;
  closed: Promise<unknown>;
  incomingUnidirectionalStreams: { getReader(): WTIncomingStreamsReader };
  close(): void;
}
interface WTOptions {
  serverCertificateHashes?: { algorithm: string; value: Uint8Array }[];
}
type WTCtor = new (url: string, opts?: WTOptions) => WTLike;

export class WebTransportTransport implements Transport {
  private wt?: WTLike;
  private onMessageCb?: (message: string) => void;
  private closed = false;

  constructor(
    private readonly url: string,
    private readonly certHashHex?: string,
  ) {}

  async initialize(): Promise<void> {
    const Ctor = (globalThis as { WebTransport?: WTCtor }).WebTransport;
    if (!Ctor) {
      throw new Error('WebTransport is not supported in this browser');
    }
    const opts: WTOptions | undefined = this.certHashHex
      ? { serverCertificateHashes: [{ algorithm: 'sha-256', value: hexToBytes(this.certHashHex) }] }
      : undefined;
    const wt = new Ctor(this.url, opts);
    this.wt = wt;
    await wt.ready;
    void this.readLoop(wt);
  }

  // Read incoming unidirectional streams; each stream, read to completion, is
  // exactly one message (the relay opens one uni-stream per broadcast).
  private async readLoop(wt: WTLike): Promise<void> {
    const streams = wt.incomingUnidirectionalStreams.getReader();
    const decoder = new TextDecoder();
    try {
      for (;;) {
        const { value: stream, done } = await streams.read();
        if (done) break;
        if (!stream) continue;
        const reader = stream.getReader();
        let msg = '';
        for (;;) {
          const chunk = await reader.read();
          if (chunk.done) break;
          if (chunk.value) msg += decoder.decode(chunk.value, { stream: true });
        }
        msg += decoder.decode();
        if (msg && this.onMessageCb) this.onMessageCb(msg);
      }
    } catch {
      /* stream errored / session closed — nothing to do */
    }
  }

  async sendMessage(): Promise<void> {
    // mdview's client never sends content upstream (it flows via HTTP POST from
    // Neovim), so this is intentionally a no-op for the WebTransport path.
  }

  onMessage(cb: (message: string) => void): void {
    this.onMessageCb = cb;
  }

  async close(): Promise<void> {
    this.closed = true;
    this.wt?.close();
  }
}

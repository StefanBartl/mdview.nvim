// ADD: Annotations
// NOTE: This is a stub/POC skeleton. Real implementation needs HTTP/3 server & TLS.

// src/client/webtransport.transport.ts

// This is a POC adapter for WebTransport. Many WebTransport types are still
// experimental in TypeScript lib definitions; safe casts are used to satisfy LSP.

import type { Transport } from "./transport.interface";

/**
 * Minimal local type definitions that describe the parts of the WebTransport API
 * used by this adapter. These are intentionally small to avoid coupling to
 * an ambient lib that may not be present.
 */

/** A bidirectional stream pair returned by createBidirectionalStream(). */
interface BidirectionalStream {
  readonly readable: ReadableStream<Uint8Array>;
  readonly writable: WritableStream<Uint8Array>;
}

/** Minimal datagrams helper shape used by some implementations. */
interface WebTransportDatagrams {
  send(data: Uint8Array): void;
}

/** A simplified WebTransport-like runtime surface used by the adapter. */
interface WebTransportLike {
  readonly incomingBidirectionalStreams?: AsyncIterable<BidirectionalStream> & ReadableStream<BidirectionalStream>;
  createBidirectionalStream?(): Promise<BidirectionalStream>;
  readonly datagrams?: WebTransportDatagrams;
  readonly ready?: Promise<void>;
  close?: () => Promise<void>;
}

/** helper: concat Uint8Array chunks (typed) */
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

/**
 * WebTransportAdapter
 *
 * Implements Transport using a WebTransport-like API when available.
 * Uses the local WebTransportLike types above to avoid `any`.
 */
export class WebTransportAdapter implements Transport {
  private session: WebTransportLike | null = null;
  private onMessageCb?: (message: string) => void;
  private readonly url: string;

  constructor(url: string) {
    // convert ws:// -> https:// for WebTransport usage
    this.url = url.replace(/^ws:/, "https:").replace(/^wss:/, "https:");
  }

  /**
   * initialize
   *
   * Feature-detects WebTransport, constructs the session object and starts
   * a background async routine to read incoming bidirectional streams.
   */
  async initialize(): Promise<void> {
    // runtime feature-detect, still avoid direct `any` casts in surface code
    const win = window as unknown as Record<string, unknown>;
    if (!("WebTransport" in win)) {
      throw new Error("WebTransport not available in this browser");
    }

    // create instance and coerce to our WebTransportLike shape
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const raw = new (win.WebTransport as any)(this.url);
    this.session = raw as WebTransportLike;

    // await ready if present
    if (this.session.ready) {
      try {
        await this.session.ready;
      } catch (err) {
        // propagate or wrap the error; keeping it visible for debugging
        throw new Error(`WebTransport session failed to become ready: ${(err as Error).message ?? String(err)}`);
      }
    }

    // Read incoming bidirectional streams in a robust way
    // If incomingBidirectionalStreams is present and async-iterable, iterate it.
    const incoming = this.session.incomingBidirectionalStreams;
    (async () => {
      try {
        if (incoming && typeof (incoming as AsyncIterable<BidirectionalStream>)[Symbol.asyncIterator] === "function") {
          for await (const stream of incoming as AsyncIterable<BidirectionalStream>) {
            // handle each inbound bidirectional stream without blocking the iterator
            void this.handleIncomingStream(stream);
          }
        } else {
          // fallback: some implementations might only expose a ReadableStream that isn't async-iterable.
          // Best-effort: try to treat it as a ReadableStream of streams.
          // If it has a getReader, consume it similarly to handleIncomingStream's readable reader.
          const maybeReadable = incoming as unknown as ReadableStream<BidirectionalStream> | undefined;
          if (maybeReadable && typeof maybeReadable.getReader === "function") {
            const reader = maybeReadable.getReader();
            while (true) {
              const result = await reader.read();
              if (result.done) break;
              if (result.value) void this.handleIncomingStream(result.value);
            }
          }
        }
      } catch (err) {
        // swallow iterator-level errors in POC, but keep debug output
         
        console.warn("webtransport incoming streams iteration error", err);
      }
    })();
  }

  /**
   * handleIncomingStream
   *
   * Consumes the readable side of a bidirectional stream, collects the bytes
   * and calls the onMessage callback with the decoded UTF-8 text.
   *
   * Accepts a strongly-typed BidirectionalStream parameter.
   */
  private async handleIncomingStream(stream: BidirectionalStream): Promise<void> {
    try {
      const reader = stream.readable.getReader();
      const chunks: Uint8Array[] = [];
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (!value) continue;
        // value is a Uint8Array (by our types); guard defensively
        const chunk = value instanceof Uint8Array ? value : new Uint8Array(value as ArrayBufferLike);
        chunks.push(chunk);
      }
      const text = new TextDecoder().decode(concat(chunks));
      if (this.onMessageCb) this.onMessageCb(text);
    } catch (err) {
      // swallow stream errors in POC but keep a helpful debug message
       
      console.warn("webtransport handleIncomingStream error", err);
    }
  }

  /**
   * sendMessage
   *
   * Uses a bidirectional stream when available for reliable, ordered delivery.
   */
  async sendMessage(message: string): Promise<void> {
    if (!this.session || typeof this.session.createBidirectionalStream !== "function") {
      throw new Error("WebTransport session not initialized or does not support bidirectional streams");
    }

    const stream = await this.session.createBidirectionalStream();
    const writer = stream.writable.getWriter();
    await writer.write(new TextEncoder().encode(message));
    // close may be undefined in some older implementations; support both flavors
    const closeResult = writer.close?.();
    if (closeResult instanceof Promise) {
      await closeResult;
    }
  }

  onMessage(cb: (message: string) => void): void {
    this.onMessageCb = cb;
  }

  /**
   * sendDatagram
   *
   * Optional: some WebTransport implementations expose datagrams.
   * This method is a no-op if datagrams are not available.
   */
  sendDatagram(data: Uint8Array): void {
    try {
      this.session?.datagrams?.send?.(data);
    } catch {
      // ignore datagram failures silently in POC
    }
  }

  /**
   * close
   *
   * Try to close the underlying session if the method is present.
   */
  async close(): Promise<void> {
    try {
      if (this.session?.close) await this.session.close();
    } catch {
      // ignore close errors in POC
    } finally {
      this.session = null;
    }
  }
}

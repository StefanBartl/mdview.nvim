// src/client/transport/transportFactory.ts
import type { Transport } from './transport.interface';
import { WebSocketTransport } from './websocket.transport';
import { WebTransportTransport, supportsWebTransport } from './webtransport.transport';

export interface CreateTransportOptions {
  /**
   * Opt in to WebTransport (HTTP/3) instead of WebSocket. Set by the client
   * from the ?transport=webtransport URL param, which the Lua side adds only
   * when `experimental.webtransport` is enabled. When true and the browser
   * supports WebTransport, it is attempted first; any failure falls back to
   * WebSocket transparently.
   */
  preferWebTransport?: boolean;
  /** HTTPS/HTTP3 URL for the WebTransport endpoint (required to attempt it). */
  webTransportUrl?: string;
  /** Hex SHA-256 of the relay's self-signed cert, pinned via serverCertificateHashes. */
  webTransportCertHash?: string;
  /** Optional diagnostics sink (routed to the relay's /clientlog). */
  log?: (message: string) => void;
}

/**
 * createTransport
 *
 * Constructs and initializes the transport for the preview client. WebSocket
 * is the default and only production transport: it's a loopback-bound preview
 * tool and WebSocket needs no TLS on localhost. WebTransport is an opt-in
 * future path (see webtransport.transport.ts and
 * docs/Roadmap/WebTransportAPI/DESIGN.md): when opted in AND supported by the
 * browser AND a WebTransport URL is provided, it is tried first, with an
 * automatic, silent fallback to WebSocket on any failure — so enabling it can
 * never break the preview, it just upgrades the transport where possible.
 */
export async function createTransport(
  wsUrl: string,
  opts: CreateTransportOptions = {},
): Promise<Transport> {
  if (opts.preferWebTransport && opts.webTransportUrl) {
    if (supportsWebTransport()) {
      try {
        const wt = new WebTransportTransport(opts.webTransportUrl, opts.webTransportCertHash);
        await wt.initialize();
        // Canonical line (scanned by :MDViewDiagnose) plus a human note.
        opts.log?.('transport active: webtransport');
        return wt;
      } catch (err) {
        opts.log?.(`transport: WebTransport failed, falling back to WebSocket: ${String(err)}`);
      }
    } else {
      opts.log?.('transport: WebTransport requested but unsupported; using WebSocket');
    }
  }

  const ws = new WebSocketTransport(wsUrl);
  await ws.initialize();
  opts.log?.('transport active: websocket');
  return ws;
}

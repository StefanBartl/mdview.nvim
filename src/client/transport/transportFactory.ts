// src/client/transport/transportFactory.ts
import type { Transport } from './transport.interface';
import { WebSocketTransport } from './websocket.transport';

/**
 * createTransport
 *
 * Constructs and initializes the WebSocket transport. WebSocket is the only
 * transport mdview.nvim uses: it's a loopback-bound preview tool, and
 * WebTransport/HTTP3 would only add TLS-certificate overhead without a
 * corresponding benefit here. The Transport interface stays in place for
 * future needs (e.g. bidirectional scrolling), not for swapping protocols.
 */
export async function createTransport(url: string): Promise<Transport> {
  const transport = new WebSocketTransport(url);
  await transport.initialize();
  return transport;
}

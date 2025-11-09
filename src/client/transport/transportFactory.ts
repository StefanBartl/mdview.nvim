// ADD: Annotations

import type { Transport } from "./transport.interface";
import { DEV_USE_WEBTRANSPORT } from "../dev-config";

/**
 * Lightweight module shapes used for dynamic imports.
 * These describe the exports expected from the two transport modules.
 */
type WebTransportModule = {
  WebTransportAdapter: new (url: string) => Transport;
};

type WebSocketModule = {
  WebSocketTransport: new (url: string) => Transport;
};

/**
 * createTransport
 *
 * Dynamically imports and constructs the appropriate Transport implementation.
 * Uses explicit casts for the import results to avoid `any` while remaining robust.
 */
export async function createTransport(url: string): Promise<Transport> {
  if (DEV_USE_WEBTRANSPORT) {
    const win = window as unknown as Record<string, unknown>;
    if ("WebTransport" in win) {
      // import webtransport module and assert it matches the WebTransportModule shape
      const mod = (await import("./webtransport.transport")) as unknown as WebTransportModule;
      const t = new mod.WebTransportAdapter(url);
      await t.initialize();
      return t;
    } else {
      // fallback to websocket-based transport
      const mod = (await import("./websocket.transport")) as unknown as WebSocketModule;
      const t = new mod.WebSocketTransport(url);
      await t.initialize();
      return t;
    }
  } else {
    const mod = (await import("./websocket.transport")) as unknown as WebSocketModule;
    const t = new mod.WebSocketTransport(url);
    await t.initialize();
    return t;
  }
}

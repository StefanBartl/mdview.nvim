// ADD: Annotations

import type { Transport } from "./transport.interface";
import { DEV_USE_WEBTRANSPORT } from "../dev-config";

export async function createTransport(url: string): Promise<Transport> {
  if (DEV_USE_WEBTRANSPORT) {
    if ((window as any).WebTransport) {
      const mod = await import("./webtransport.transport");
      const t = new mod.WebTransportAdapter(url);
      await t.initialize();
      return t as Transport;
    } else {
      const mod = await import("./websocket.transport");
      const t = new mod.WebSocketTransport(url);
      await t.initialize();
      return t as Transport;
    }
  } else {
    const mod = await import("./websocket.transport");
    const t = new mod.WebSocketTransport(url);
    await t.initialize();
    return t as Transport;
  }
}

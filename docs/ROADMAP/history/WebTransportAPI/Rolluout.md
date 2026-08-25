> ⚠️ **OUTDATED / dropped.** Describes a transport abstraction with
> `dev-config.ts` / `webtransport.transport.ts` (both deleted). WebTransport was
> not implemented (see `../../DONE.md` BUGS #3). History only.

---

## Agreement and architecture proposal (short)

Yes — agree with the proposal. The cleanest, maintainable solution is a
**transport adapter abstraction** with clearly separated implementations in
separate files (no mixing of WebSocket and WebTransport in one file). The
selection mechanism is dev-controllable (a feature flag in the source), and the
client additionally does a **feature detect** on `window.WebTransport`. Depending
on the flag + detection, exactly **one** implementation is loaded dynamically.
That keeps the code modular and testable, and the risk low.

---

## Principles / requirements for the implementation

* **Single responsibility:** every transport implementation in its own file (`websocket.transport.ts`, `webtransport.transport.ts`).
* **Transport interface:** a shared TypeScript interface (`Transport`) describes the API (sendMessage, onMessage, sendDatagram optional, openStream optional, close).
* **Factory/bootstrap:** `transportFactory.ts` decides (dev flag + feature detect) and loads exactly the needed implementation via a dynamic `import()`.
* **Dev opt-in:** the flag `DEV_USE_WEBTRANSPORT = true|false` in `src/client/dev-config.ts` (for developers in the source only, not in the user config).
* **Fallback:** if the flag is true but the browser does not support it or the server is not WebTransport-ready, fall back to WebSocket.
* **No mixing:** never mix WebSocket and WebTransport APIs in one implementation file.
* **Tests & mocks:** unit tests for `transportFactory` + mock implementations, E2E with Playwright/headless for both transports.
* **Docs:** a README section: how to set the opt-in, how to implement the WebTransport PoC file.

---

## Recommended file structure (client)

```
src/
└─ client/
   ├─ transport/
   │  ├─ transport.interface.ts       # Transport interface (shared)
   │  ├─ websocket.transport.ts       # WebSocket implementation
   │  └─ webtransport.transport.ts    # WebTransport implementation (stub for now)
   ├─ transportFactory.ts            # decides which transport to import
   ├─ dev-config.ts                  # DEV_USE_WEBTRANSPORT flag
   ├─ main.ts                        # app bootstrapping — uses transportFactory
   └─ ... (other client files)
```

---

## The transport interface (TypeScript)

```ts
// src/client/transport/transport.interface.ts
// English comments per project rules

export interface Transport {
  /**
   * Open / initialize the transport (connect or wait for ready).
   * May perform async handshake.
   */
  initialize(): Promise<void>;

  /**
   * Send a textual message (JSON encoded).
   */
  sendMessage(message: string): Promise<void>;

  /**
   * Register callback for inbound textual messages.
   */
  onMessage(cb: (message: string) => void): void;

  /**
   * Optional: send a best-effort datagram (unreliable).
   */
  sendDatagram?(data: Uint8Array): void;

  /**
   * Close the transport.
   */
  close(): Promise<void>;
}
```

---

## WebSocket implementation (TS)

```ts
// src/client/transport/websocket.transport.ts
// English comments in code

import type { Transport } from "./transport.interface";

export class WebSocketTransport implements Transport {
  private ws!: WebSocket;
  private url: string;
  private onMessageCb?: (message: string) => void;

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
      // simple wait / retry pattern could be added
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
```

---

## WebTransport implementation (TS stub / placeholder)

```ts
// src/client/transport/webtransport.transport.ts
// English comments in code
// NOTE: This is a stub/POC skeleton. Real implementation needs HTTP/3 server & TLS.

import type { Transport } from "./transport.interface";

export class WebTransportAdapter implements Transport {
  private session!: WebTransport;
  private onMessageCb?: (message: string) => void;
  private url: string;

  constructor(url: string) {
    // use https scheme for WebTransport
    this.url = url.replace(/^ws:/, "https:").replace(/^wss:/, "https:");
  }

  async initialize(): Promise<void> {
    // Feature detect at runtime: abort if not supported
    if (!(window as any).WebTransport) {
      throw new Error("WebTransport not available in this browser");
    }

    this.session = new (window as any).WebTransport(this.url);
    await this.session.ready;

    // wire incoming bidirectional streams (example)
    (async () => {
      for await (const stream of this.session.incomingBidirectionalStreams) {
        const reader = stream.readable.getReader();
        const chunks: Uint8Array[] = [];
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          chunks.push(value);
        }
        const text = new TextDecoder().decode(concat(chunks));
        if (this.onMessageCb) this.onMessageCb(text);
      }
    })();
  }

  async sendMessage(message: string): Promise<void> {
    const { writable } = await this.session.createBidirectionalStream();
    const writer = writable.getWriter();
    await writer.write(new TextEncoder().encode(message));
    await writer.close();
  }

  onMessage(cb: (message: string) => void): void {
    this.onMessageCb = cb;
  }

  sendDatagram(data: Uint8Array): void {
    this.session.datagrams?.send(data);
  }

  async close(): Promise<void> {
    await this.session.close();
  }
}

/** helper to concat Uint8Array chunks */
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
```

> Note: the WebTransport implementation above is a PoC skeleton. On the server side HTTP/3 + TLS is required — hence the file is a stub for now, activated on opt-in.

---

## The transport factory (dynamic loader)

```ts
// src/client/transportFactory.ts
// English comments in code

import { Transport } from "./transport/transport.interface";
import { DEV_USE_WEBTRANSPORT } from "./dev-config";

// Returns a transport instance. This function uses dynamic import so that
// the WebTransport implementation is only loaded when selected.
export async function createTransport(url: string): Promise<Transport> {
  // Developer opt-in at build/source level
  if (DEV_USE_WEBTRANSPORT) {
    // runtime feature detect
    if ((window as any).WebTransport) {
      const mod = await import("./transport/webtransport.transport");
      const t = new mod.WebTransportAdapter(url);
      await t.initialize();
      return t;
    } else {
      // fallback to ws if browser does not support WebTransport
      const mod = await import("./transport/websocket.transport");
      const t = new mod.WebSocketTransport(url);
      await t.initialize();
      return t;
    }
  } else {
    // default path: WebSocket
    const mod = await import("./transport/websocket.transport");
    const t = new mod.WebSocketTransport(url);
    await t.initialize();
    return t;
  }
}
```

---

## The dev opt-in flag (dev only)

```ts
// src/client/dev-config.ts
// English comments in code
// Toggle this flag in source during development to test WebTransport branch.
// NOTE: not exposed to end users in config for now.

export const DEV_USE_WEBTRANSPORT = false;
```

---

## Integration into `main.ts`

```ts
// src/client/main.ts
// English comments in code

import { createTransport } from "./transportFactory";

async function boot() {
  const url = `ws://${location.host}/ws`; // factory may convert if using WebTransport
  const transport = await createTransport(url);

  transport.onMessage((msg) => {
    // handle incoming render_update etc.
    console.log("message", msg);
  });

  // Example usage
  await transport.sendMessage(JSON.stringify({ type: "hello" }));
}

boot().catch((err) => console.error("boot failed:", err));
```

---

## Server-side adjustments (short)

* In the long run the server has to be **dual stack**: expose both a `/ws` (WebSocket) and a `/wt` (WebTransport) endpoint. For now `/ws` is enough.
* The WebTransport endpoint initially requires a **separate server binary** (Rust/QUIC or an edge runtime) or an experimental Node lib. Therefore: implement the WebTransport endpoint later as a separate process `webtransport.server.*` and document how to run it.
* Keep the existing WebSocket server unchanged.

---

## Advantages of this approach

* **Minimal initial effort:** only the factory + a separate stub file; no change to the existing WebSocket code is needed.
* **Clean code:** no mixing of transports; every implementation stays readable.
* **Feature toggle:** developers can test WebTransport locally without user configuration or breaking changes.
* **Future-safe:** ready for a real WebTransport PoC later, without refactoring pain.

---

## Risks / disadvantages

* **Dynamic imports increase bundle complexity:** Vite bundles both files, but lazy loading keeps the runtime cost low. Keep the CI/build documentation in mind.
* **Server complexity later:** running an HTTP/3 WebTransport server is more work (TLS, QUIC). For now: keep WebSocket as the default.
* **Testing effort:** additional tests are needed (mocks, integration).

---

## Test & implementation checklist (task-oriented, with checkboxes)

* [ ] Create `src/client/transport/transport.interface.ts`
* [ ] Create `src/client/transport/websocket.transport.ts` (finish it / unit tests)
* [ ] Create `src/client/transport/webtransport.transport.ts` as a PoC stub (no server dependency yet)
* [ ] Create `src/client/transportFactory.ts` (dev opt-in logic + dynamic import)
* [ ] Create `src/client/dev-config.ts` with `DEV_USE_WEBTRANSPORT = false`
* [ ] Adapt `src/client/main.ts` to use `createTransport`
* [ ] Unit tests for `transportFactory` (mock window.WebTransport + mock imports)
* [ ] Integration test for the WebSocket path (existing server)
* [ ] Documentation: a README section "Dev opt-in WebTransport (how to)"
* [ ] Create server stub notes: `src/server/webtransport.server.*` (todo) and document the requirements (HTTP/3, TLS)
* [ ] Add a CI job entry (optional) to run the transport factory unit tests

---

## Further: notes for the build / Vite

* Dynamic `import()` works with Vite; both implementations are bundled, but only the class actually imported gets instantiated. If the WebTransport implementation later turns out to be too large given the Node APIs/types, a separate chunking/conditional build strategy can be used.
* Watch out for `tsconfig` and the linter: references to DOM types (`WebTransport`) are browser-only — the typedefs should appear only in client TS files (no `lib: ["DOM"]` in the server tsconfig).

---

## Conclusion

The proposed route is robust, minimally invasive and future-proof: a small factory + a dev flag + separate implementation files give exactly the separation wanted. No large risks arise as long as WebTransport remains only a dev-opt-in stub at first and WebSocket stays the default.

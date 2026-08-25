> ⚠️ **OUTDATED / dropped.** This WebTransport evaluation refers to the old
> Node/TS stack (`dev-config.ts`, `webtransport.transport.ts` — both deleted).
> The decision has been made (see `../../DONE.md` BUGS #3): WebTransport brings
> no benefit for small text updates and forces TLS on localhost. **Not pursued
> further.** Kept only as research history.

---

# Theoretical upgrade evaluation: from WebSocket to WebTransport

## Table of content

  - [Short version (one sentence)](#short-version-one-sentence)
  - [What WebTransport is — briefly, technically](#what-webtransport-is--briefly-technically)
  - [Important effects for mdview.nvim — what you would gain](#important-effects-for-mdviewnvim--what-you-would-gain)
  - [What you would (concretely) lose or complicate](#what-you-would-concretely-lose-or-complicate)
  - [Which changes to the existing code would be needed — a rough guide](#which-changes-to-the-existing-code-would-be-needed--a-rough-guide)
    - [1) Architecture & API layer: introduce a protocol abstraction](#1-architecture--api-layer-introduce-a-protocol-abstraction)
    - [2) Server: provide HTTP/3 + a WebTransport server](#2-server-provide-http3--a-webtransport-server)
    - [3) Client (browser/TS): replace WebSocket usage with the WebTransport API + fallback](#3-client-browserts-replace-websocket-usage-with-the-webtransport-api--fallback)
    - [4) Neovim Lua plugin: no big API changes, but an ops switch](#4-neovim-lua-plugin-no-big-api-changes-but-an-ops-switch)
    - [5) Protocol evolution & backward compatibility](#5-protocol-evolution--backward-compatibility)
  - [Practical changes to the stack and a dev/deploy checklist](#practical-changes-to-the-stack-and-a-devdeploy-checklist)
  - [Security, privacy, and operational considerations](#security-privacy-and-operational-considerations)
  - [Conclusion & recommendation (concretely for mdview.nvim)](#conclusion--recommendation-concretely-for-mdviewnvim)
  - [Sources / further reading](#sources--further-reading)

---

## Short version (one sentence)

mdview.nvim can be ported from WebSocket to WebTransport in order to use HTTP/3/QUIC features (multiplexed streams, unreliable datagrams, better congestion control) — but it requires non-trivial changes to the server stack, TLS/HTTP-3 provisioning, fallback handling and tests; a nice side effect is potentially lower latency and native stream/data semantics. ([developer.mozilla.org][1])

---

## What WebTransport is — briefly, technically

WebTransport is a modern web API for bidirectional low-latency data transport, built on HTTP/3/QUIC. It offers multiplexed reliable streams (like TCP), unidirectional streams and *unreliable* datagrams (like UDP) over the same connection channel, all encrypted and with modern congestion control. ([developer.mozilla.org][1])

---

## Important effects for mdview.nvim — what you would gain

* **Multiplexing without head-of-line blocking:** several logical streams (e.g. a renderer stream, a control stream, a file-diff stream) run in parallel without delaying each other on packet loss. That reduces perceptible latency on large updates. ([developer.mozilla.org][1])
* **Unreliable datagrams:** small, latency-critical updates (e.g. cursor positions, scroll deltas, telemetry pings) can optionally be sent as datagrams, without retransmit overhead. Suitable for UI snappiness. ([gocodeo.com][2])
* **Better network performance in mobile/wireless environments:** QUIC has more modern congestion control and faster recovery than TCP/TLS. → lower RTT / a better interactive experience. ([DEV Community][3])
* **Security / TLS out of the box:** WebTransport runs over HTTP/3 (QUIC) and uses the same TLS underpinning as HTTPS; no plain-TCP downgrade is possible. ([developer.mozilla.org][1])

---

## What you would (concretely) lose or complicate

* **Server support and maturity:** as of 2025, Node.js has no robust, native, widely used WebTransport core API; solutions are experimental, while Rust/C++/cloud-provider implementations are more stable. That means more ops effort (HTTP/3, QUIC, certificates) or a dependency on a cloud provider (Cloudflare, Fastly, etc.). ([videosdk.live][4])
* **Browser compatibility:** modern Chromium browsers (Chrome/Edge) adopt WebTransport earlier/more robustly; other browsers follow — feature detection + a fallback to WebSocket has to be built in. ([developer.mozilla.org][1])
* **Deploy/network complexity:** HTTP/3/QUIC can struggle with middleboxes/proxies/TLS MitM; in local dev setups you often have to set up TLS certificates & Chrome flags/trust or use a cloud proxy. ([videosdk.live][5])
* **Ecosystem and libraries:** many Node libs/hosting platforms expect HTTP/1.1/2 — WebTransport requires a specific server stack or worker runtimes (e.g. Cloudflare Workers, Rust-based servers), or experimental Node libs. ([videosdk.live][4])

---

## Which changes to the existing code would be needed — a rough guide

### 1) Architecture & API layer: introduce a protocol abstraction

* **Why:** the existing code is bound directly to the WebSocket API (`ws`). What is needed is a **transport adapter layer** that exposes both implementations (WebSocket / WebTransport) and delivers the same events/primitives: `open`, `close`, `sendMessage`, `sendDatagram`, `openStream`, `closeStream`, `onStreamData`, `onDatagram`.
* **Concretely:** a new module `adapter/transport.ts` (JS/TS) with an interface `Transport` and two implementations, `WebSocketTransport` + `WebTransportAdapter`. The Neovim Lua side keeps calling the same HTTP/JSON endpoints / control endpoints; only the client/server uses the transport adapters internally.

### 2) Server: provide HTTP/3 + a WebTransport server

* **Why:** WebTransport runs over HTTP/3. Node-native servers are missing; what is needed is:

  * Option A: a Rust/C++ HTTP/3 server (e.g. the `quinn`, `wtransport` crates) as a separate process — very performant. ([GitHub][6])
  * Option B: a Cloudflare Worker / edge runtime with WebTransport support (a cloud provider) — simple deployment, TLS & HTTP/3 out of the box. ([The Cloudflare Blog][7])
  * Option C: experimental Node libraries implementing WebTransport (if available) — a higher maintenance risk. ([videosdk.live][4])
* **Concretely:** `src/server/webtransport.server.(ts|rs)` — the server implements WebTransport session handling, maps sessions → client IDs, provides the HTTP endpoint `/render` for compatibility, and can open server-initiated streams to the client. The server exports the same WS-style JSON events for backwards compatibility.

### 3) Client (browser/TS): replace WebSocket usage with the WebTransport API + fallback

* **What to change:** replace `const ws = new WebSocket(url)` with `const transport = new WebTransport(url)`. Use `transport.datagrams` (optional) and `transport.incomingUnidirectionalStreams`/`outgoing...` for stream semantics. Implement a fallback to WebSocket when `WebTransport` is not available. ([developer.mozilla.org][1])
* **Example (TypeScript) — simplified:**

```ts
// transport-adapter.ts
// English comments (code must have English comments)

export interface Transport {
  sendMessage(msg: string): Promise<void>;
  onMessage(cb: (msg: string) => void): void;
  sendDatagram?(data: Uint8Array): void;
  close(): Promise<void>;
}

/* WebTransport implementation */
export class WebTransportAdapter implements Transport {
  private session: WebTransport;
  private reader?: ReadableStreamDefaultReader<Uint8Array>;

  constructor(url: string) {
    // create WebTransport session; requires wss->https mapping and HTTP/3
    this.session = new WebTransport(url);
  }

  async initialize() {
    // Wait for ready
    await this.session.ready;
    // Start reading from incoming unidirectional streams (example)
    const streamIter = this.session.incomingBidirectionalStreams;
    (async () => {
      for await (const stream of streamIter) {
        const reader = stream.readable.getReader();
        // Read and decode, call onMessage callback
      }
    })();
  }

  async sendMessage(msg: string) {
    // allocate a new outgoing bidirectional stream and write
    const stream = await this.session.createBidirectionalStream();
    const writer = stream.writable.getWriter();
    await writer.write(new TextEncoder().encode(msg));
    await writer.close();
  }

  sendDatagram(data: Uint8Array) {
    // datagrams are best-effort, low-latency
    if (this.session.datagrams) {
      this.session.datagrams.send(data);
    }
  }

  async close() {
    await this.session.close();
  }
}

/* Fallback factory */
export async function createTransport(url: string): Promise<Transport> {
  if ((window as any).WebTransport) {
    const t = new WebTransportAdapter(url.replace('ws://','https://').replace('ws:','https:'));
    await t.initialize();
    return t;
  } else {
    // fallback to WebSocketTransport (implement using existing ws logic)
    return new WebSocketTransport(url);
  }
}
```

(Note: `WebTransport` URLs use the `https` scheme and require HTTP/3 on the server.)

### 4) Neovim Lua plugin: no big API changes, but an ops switch

* **What to do:**

  * The plugin config offers `server_transport: "websocket" | "webtransport"`.
  * The start/stop logic spawns either `node server` (ws) or the `webtransport server` (a Rust/Bun wrapper) depending on the config.
  * Keep the control endpoint `/api/control` over HTTPS/HTTP for out-of-band commands (still REST).
* **In addition:** for local dev: document the TLS cert setup, or use a proxy (ngrok/Cloudflare Tunnel) that terminates TLS + provides HTTP/3.

### 5) Protocol evolution & backward compatibility

* **Dual stack:** the server should offer both a WebSocket endpoint (legacy) and a WebTransport endpoint (modern); the client feature-detects and picks. That way existing users are not forced to upgrade. ([WebSocket.org][8])

---

## Practical changes to the stack and a dev/deploy checklist

1. **Decide server implementation**

   * Fastest path for production: deploy a Rust WebTransport server (quinn/wtransport) or use Cloudflare Workers with WebTransport support for hosting. ([GitHub][6])
   * Experiment path: try community Node libs that provide WebTransport support for dev; be aware of experimental status. ([videosdk.live][4])

2. **TLS + HTTP/3**

   * Local dev: generate self-signed certs and configure browser to trust them, or use a reverse proxy/Cloudflare Tunnel. Document this step thoroughly. ([JavaScript Development Space][9])

3. **Transport adapter library in repo**

   * Add `src/client/transport/*` + `src/server/transport/*` and interfaces. Keep WebSocket implementation unchanged until WebTransport proven.

4. **Fallback & Feature detect**

   * Client side: `if ('WebTransport' in window) { use WebTransport } else { fallback to WebSocket }`. Add telemetry to measure how many users can use WebTransport. ([developer.mozilla.org][1])

5. **Testing**

   * Unit tests for transport adapters (mocks).
   * Integration tests: local Rust server + browser automation (Playwright with HTTP/3 support) to test streams & datagrams.
   * Performance benchmarks (compare RTT, throughput, CPU) for typical file sizes.

6. **CI adjustments**

   * Add a matrix job to test WebTransport implementation only if server runtime available (Rust toolchain or special Node flags). Use container images with HTTP/3 capable servers.

---

## Security, privacy, and operational considerations

* **TLS mandatory:** WebTransport requires HTTP/3/TLS; certificate management is mandatory. For local dev one must accept self-signed certs or use a trusted dev proxy. ([JavaScript Development Space][9])
* **CORS & SameOrigin:** WebTransport session establishment follows HTTP rules; server must allow origins and handle credentials appropriately.
* **Firewall / NAT:** QUIC uses UDP; some corporate networks block UDP which will prevent WebTransport from working — must provide WebSocket fallback.
* **Observability:** QUIC/HTTP3 stacks require different metrics tools; monitor connection establishment, stream counts, datagram loss rates.

---

## Conclusion & recommendation (concretely for mdview.nvim)

* **Short term:** keep WebSocket as the default; implement a **transport adapter** abstraction and create an opt-in WebTransport adapter implementation for experimental branches. That keeps the codebase stable and gives testable progress. ([WebSocket.org][8])
* **Medium term:** implement and document a Rust-based WebTransport server PoC (e.g. with `wtransport`), including a local TLS setup and Playwright E2E tests. Compare the performance with WebSocket. ([GitHub][6])
* **Long term:** if browser support and the Node ecosystem stay stable, make WebTransport the default in a major version; until then, offer a dual stack.

---

## Sources / further reading

* MDN — WebTransport API (overview & usage). ([developer.mozilla.org][1])
* WebTransport concepts: streams, datagrams, QUIC/HTTP3 basics. ([gocodeo.com][2])
* Status / caveats in the Node.js ecosystem (server support still limited / experimental). ([videosdk.live][4])
* Rust community WebTransport server examples & PoC libs (wtransport). ([GitHub][6])

---

[1]: https://developer.mozilla.org/en-US/docs/Web/API/WebTransport_API?utm_source=chatgpt.com "WebTransport API - MDN Web Docs"
[2]: https://www.gocodeo.com/post/webtransport-explained-low-latency-communication-over-http-3?utm_source=chatgpt.com "Low-Latency Communication over HTTP/3"
[3]: https://dev.to/hexshift/how-to-build-real-time-applications-with-webtransport-the-successor-to-websockets-3aik?utm_source=chatgpt.com "How to Build Real-Time Applications with WebTransport"
[4]: https://www.videosdk.live/developer-hub/webtransport/nodejs-webtransport?utm_source=chatgpt.com "Node.js WebTransport: The Next Generation of Real-Time ..."
[5]: https://www.videosdk.live/developer-hub/webtransport/webtransport-server?utm_source=chatgpt.com "How to Implement WebTransport Server?"
[6]: https://github.com/BiagioFesta/wtransport?utm_source=chatgpt.com "BiagioFesta/wtransport: Async-friendly WebTransport ..."
[7]: https://blog.cloudflare.com/de-de/bringing-node-js-http-servers-to-cloudflare-workers/?utm_source=chatgpt.com "Bringing Node.js HTTP servers to Cloudflare Workers"
[8]: https://websocket.org/guides/future-of-websockets/?utm_source=chatgpt.com "The Future of WebSockets: HTTP/3 and WebTransport"
[9]: https://jsdev.space/webtransport-api/?utm_source=chatgpt.com "Exploring the WebTransport API: A New Era of Web ..."

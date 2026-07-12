# WebTransport (HTTP/3) — opt-in future transport

> **Status: IMPLEMENTED (end-to-end), pending real-browser verification.**
> `experimental.webtransport = true` now: the Lua side spawns the relay with
> `--webtransport`; the relay generates a short-lived self-signed ECDSA cert,
> serves `/wt` over HTTP/3 (UDP, same port), and prints `wt cert-hash: <hex>`;
> the runner captures the hash → launcher appends `&transport=webtransport&
> wtcerthash=<hex>` → the client pins it via `serverCertificateHashes` and reads
> one message per incoming unidirectional stream. The client still falls back to
> WebSocket on any failure. The end-to-end handshake needs a real HTTP/3-capable
> browser to verify (can't run headless in CI); the Go pieces (cert gen, build)
> are unit-tested. Requires a relay binary built with WebTransport support
> (v0.2.0+). Design notes below.

## Why opt-in / why not default

For a loopback-bound preview streaming small text updates, WebSocket is the
right default: no TLS required on `localhost`, trivial to debug. WebTransport
(HTTP/3 over QUIC) **requires TLS even on loopback**, which forces certificate
handling. It's kept as an opt-in "future tech" path so the plumbing is ready if
we ever want QUIC's benefits (multiplexed streams, unreliable datagrams for
scroll pings, head-of-line-blocking avoidance), without paying the TLS cost by
default.

## What already exists (this repo)

- **Client transport** — `src/client/transport/webtransport.transport.ts`
  implements the `Transport` interface over a WebTransport bidirectional stream
  (UTF-8 text frames, mirroring the WebSocket path). `supportsWebTransport()`
  feature-detects the API.
- **Factory selection + fallback** — `transportFactory.ts` tries WebTransport
  first when `preferWebTransport` is set and the URL is provided, and falls
  back to WebSocket on any failure. Covered by
  `tests/client/transportFactory.test.ts`.
- **Opt-in wiring** — `experimental.webtransport` (Lua config) →
  `&transport=webtransport` on the browser URL (`launcher.resolve_browser_url`)
  → `main.ts` reads `?transport=` and passes `preferWebTransport` +
  `webTransportUrl` (`https://<host>/wt?...`) to the factory.

## What the relay backend needs (the remaining work)

1. **HTTP/3 server.** Add `github.com/quic-go/quic-go` +
   `github.com/quic-go/webtransport-go`. Serve QUIC on the **same UDP port
   number** as the existing TCP HTTP port (browsers reach HTTP/3 on the UDP
   port advertised via `Alt-Svc`, but for a direct WebTransport URL the client
   dials the given authority over QUIC directly).

2. **TLS certificate.** WebTransport on loopback works without a public CA by
   passing `serverCertificateHashes` to the browser's `new WebTransport(url,
   { serverCertificateHashes: [{ algorithm: 'sha-256', value: <hash> }] })`.
   Constraints imposed by browsers (Chromium):
   - certificate must be ECDSA (P-256),
   - validity ≤ 14 days,
   - the SHA-256 of the DER cert is what the client pins.
   Generate a fresh short-lived self-signed cert per session in Go at startup,
   compute its SHA-256, and expose the hash so Lua can pass it to the client.

3. **Hash delivery to the client.** Extend the spawn/handshake so the cert hash
   reaches the browser URL (e.g. print `wt cert-hash: <hex>` on the relay's
   stdout — the runner already parses stdout for the port — and have Lua append
   `&wtcerthash=<hex>`; `main.ts` would parse it into `serverCertificateHashes`
   and `webtransport.transport.ts` would forward it as the second
   `WebTransport` constructor argument).

4. **`/wt` handler.** Upgrade the request via `webtransport-go`'s `Server`,
   accept a bidirectional stream, and reuse the existing `relay.Registry`
   room model (key = document path, token-gated, Origin-checked) exactly like
   `/ws`. Push `LastPayload` on join; broadcast updates and ephemeral scroll
   pings the same way. Datagrams could later carry scroll pings unreliably.

5. **Fallback stays authoritative.** Keep `/ws` unchanged. The client already
   falls back, so a WebTransport handshake failure (cert expiry, unsupported
   browser, UDP blocked) must never degrade the preview.

## Testing plan for the backend

- Go: unit-test cert generation (ECDSA/P-256, ≤14d) and that the `/wt` handler
  reuses `Registry` (room isolation, token/Origin rejection) — same table-driven
  style as `internal/relay/*_test.go`.
- Manual E2E: a real Chromium with `chrome://flags` HTTP/3 enabled, opt-in on,
  confirm `[client] transport: using WebTransport` in `:MDViewShowWebLogs`, and
  confirm content + scroll still work. This step needs a real browser and can't
  run headless in CI.

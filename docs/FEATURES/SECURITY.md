# Security

mdview.nvim positions itself as a security/performance-focused alternative to
existing Neovim Markdown-preview plugins (see the README). Two mechanisms
carry that claim: a relay that only ever admits the local machine, and a
renderer that never emits unsanitized HTML (covered in
[RENDERING.md](RENDERING.md)). This file covers the former.

## Loopback-only relay with per-session token and Origin checks

The relay binds only to `127.0.0.1`/`localhost` — never a routable interface
— and every write endpoint additionally requires a per-session token
generated at `:MDView start` time, compared with a constant-time comparison
(`crypto/subtle`) so response timing can't be used to brute-force it. An
empty expected token never validates, so a misconfigured session fails
closed rather than open. WebSocket upgrades are further restricted to an
exact Origin allowlist (`http://localhost:<port>`, `http://127.0.0.1:<port>`)
— anything else, including a missing `Origin` header (which real browsers
always send), is rejected. This is the primary defense against DNS-rebinding
and cross-site WebSocket hijacking of a server that's otherwise reachable by
any process on the same machine.

- **Tab:** true
- **Module:** `native/server/internal/relay/auth.go` (`ValidToken`, `AllowedOrigins`, `IsAllowedOrigin`), `lua/mdview/helper/gen_token.lua`

### Why this matters more than it might look

A loopback bind alone is not sufficient on a shared or multi-user machine —
anything already running as the same user (or, for a browser-originated
attack, any web page open in the same browser making cross-origin requests to
`127.0.0.1`) can reach a loopback port. The token turns "reachable" into
"reachable and authorized"; the Origin check specifically closes the
WebSocket-hijacking angle a token alone doesn't cover, since a malicious page
could otherwise open a WebSocket to the relay using credentials it never saw
(no token needed for the browser to *initiate* a same-origin-looking
handshake — Origin is the only signal available to refuse it).

## Port selection is race-free

The relay doesn't just probe whether a preferred port looks free and then
bind it a moment later (a check that a second process could race) — it binds
to test, immediately releases, and scans upward through up to 200 candidate
ports if the preferred one is taken. Used both for the main relay
(`server_port`, default `43219`) and standalone mode's separate port range.

- **Module:** `native/server/internal/relay/port.go` (`FindFreePort`)

## WebTransport certificate pinning

When `experimental.webtransport` is enabled, the relay also serves an HTTP/3
endpoint over a short-lived, self-signed ECDSA P-256 certificate (≈13-day
validity, under Chromium's 14-day cap for pinned certs) and prints its
SHA-256 fingerprint, which the client passes as `serverCertificateHashes` to
trust that exact certificate without a public CA — appropriate for a
loopback-only connection with no real external verifier. WebSocket remains
the default transport; WebTransport is opt-in future-tech with no real
latency win on loopback today.

- **Module:** `native/server/internal/relay/cert.go` (`GenerateWebTransportCert`), `native/server/webtransport.go`
- **Config:** `experimental.webtransport` (default `false`)

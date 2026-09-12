# Security

mdview.nvim positions itself as a security- and performance-focused
alternative to existing Neovim Markdown-preview plugins — it was inspired
by, and contrasts most directly with,
[iamcco/markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim).
Two mechanisms carry that claim: a relay that only ever admits the local
machine, and a renderer that never emits unsanitized HTML (covered in
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

## Release downloads are checksummed, bounded, and never trusted half-written

`:MDView start` bootstraps the platform-matching `mdview-server` binary and
the prebuilt browser client bundle from GitHub Releases on first use (same
pattern as mason.nvim/nvim-treesitter). Each asset is downloaded via `curl`
as an argv array (no shell interpolation) and verified against the release's
own `checksums.txt` (SHA-256) before being treated as installed; a mismatch
deletes the file rather than leaving a wrong-but-present binary around to be
picked up on the next start.

The download itself is bounded — `--max-time 60` and `--max-filesize
100MB` — since `curl_download` runs synchronously on the main loop: without
a timeout, a hung connection would freeze Neovim indefinitely, and without a
size cap, a compromised or misconfigured release host could exhaust disk
space instead of just failing. A failed download (timeout, oversize, network
error) also has its partial output file removed immediately — the next
`:MDView start` treats *any* file already on disk at the target path as
"already installed" without re-checksumming it, so leaving a truncated
binary there would have meant it silently skips verification and gets
executed as the server process on the following start.

- **Module:** `lua/mdview/adapter/install.lua` (`curl_download`,
  `ensure_asset`, `expected_checksum`, `file_sha256`)
- **Config:** `install.repo`, `install.version` (pin a fork or a specific
  release instead of the default)

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

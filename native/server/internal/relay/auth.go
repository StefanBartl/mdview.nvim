package relay

import (
	"crypto/subtle"
	"fmt"
)

// ValidToken reports whether got matches expected using a constant-time
// comparison, so response timing cannot be used to brute-force the token.
// An empty expected token never validates (fail closed if misconfigured).
func ValidToken(expected, got string) bool {
	if expected == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(expected), []byte(got)) == 1
}

// AllowedOrigins returns the exact Origin header values accepted for a
// WebSocket upgrade on the given port. Anything else (including a missing
// Origin header, which real browsers always send) is rejected, which is the
// primary defense against DNS-rebinding and cross-site WebSocket hijacking
// of a loopback-bound server.
func AllowedOrigins(port int) map[string]struct{} {
	return map[string]struct{}{
		fmt.Sprintf("http://localhost:%d", port): {},
		fmt.Sprintf("http://127.0.0.1:%d", port): {},
	}
}

// IsAllowedOrigin reports whether origin is one of AllowedOrigins(port).
func IsAllowedOrigin(origin string, port int) bool {
	_, ok := AllowedOrigins(port)[origin]
	return ok
}

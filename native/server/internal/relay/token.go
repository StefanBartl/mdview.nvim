package relay

import (
	"crypto/rand"
	"encoding/hex"
)

// GenerateToken returns a fresh 256-bit session token as a hex string.
//
// Normally the Lua side generates the token and passes it in via --token, and
// this is unused. In standalone mode (--watch) there is no Lua side, so the
// process mints its own. crypto/rand rather than math/rand: the token is the
// only thing standing between the relay and any other local process that can
// reach the loopback port, so it must not be predictable from the start time.
func GenerateToken() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

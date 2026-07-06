// Package relay implements the mdview relay server: a thin process that
// authenticates a single Neovim instance, accepts raw markdown text over
// HTTP, and fans it out to browser tabs watching the same document over
// WebSocket. It never renders or touches HTML.
package relay

import (
	"fmt"
	"net"
)

const maxPortAttempts = 200

// FindFreePort returns preferred if a listener can bind to it on the loopback
// interface, otherwise scans upward for the next free port. Binding
// (not just probing) is required so the check is race-free against a second
// probe from FindFreePort's caller a moment later.
func FindFreePort(preferred int) (int, error) {
	for p := preferred; p < preferred+maxPortAttempts; p++ {
		if isPortFree(p) {
			return p, nil
		}
	}
	return 0, fmt.Errorf("no free port found in range [%d, %d)", preferred, preferred+maxPortAttempts)
}

func isPortFree(port int) bool {
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return false
	}
	_ = ln.Close()
	return true
}

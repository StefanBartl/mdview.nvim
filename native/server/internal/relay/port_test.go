package relay

import (
	"net"
	"testing"
)

func TestFindFreePort_ReturnsPreferredWhenFree(t *testing.T) {
	// Bind a throwaway listener to learn a genuinely free ephemeral port, then
	// release it and confirm FindFreePort picks that exact port back up.
	probe, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to obtain ephemeral port for test setup: %v", err)
	}
	preferred := probe.Addr().(*net.TCPAddr).Port
	if err := probe.Close(); err != nil {
		t.Fatalf("failed to release probe listener: %v", err)
	}

	got, err := FindFreePort(preferred)
	if err != nil {
		t.Fatalf("FindFreePort returned error: %v", err)
	}
	if got != preferred {
		t.Fatalf("expected FindFreePort to return %d, got %d", preferred, got)
	}
}

func TestFindFreePort_FallsBackWhenPreferredTaken(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to bind occupied listener: %v", err)
	}
	defer ln.Close()
	occupied := ln.Addr().(*net.TCPAddr).Port

	got, err := FindFreePort(occupied)
	if err != nil {
		t.Fatalf("FindFreePort returned error: %v", err)
	}
	if got == occupied {
		t.Fatalf("expected FindFreePort to skip occupied port %d", occupied)
	}
}

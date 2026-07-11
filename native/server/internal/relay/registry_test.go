package relay

import (
	"errors"
	"testing"
)

// fakeConn records every payload sent to it, so tests can assert exactly
// which connections received a broadcast without needing a real socket.
type fakeConn struct {
	received [][]byte
	failNext bool
}

func (f *fakeConn) Send(payload []byte) error {
	if f.failNext {
		f.failNext = false
		return errors.New("simulated send failure")
	}
	f.received = append(f.received, payload)
	return nil
}

func TestRegistry_BroadcastOnlyReachesSameRoom(t *testing.T) {
	r := NewRegistry()
	a1 := &fakeConn{}
	a2 := &fakeConn{}
	b1 := &fakeConn{}

	r.Join("/doc/a.md", a1)
	r.Join("/doc/a.md", a2)
	r.Join("/doc/b.md", b1)

	r.Broadcast("/doc/a.md", []byte("hello a"))

	if len(a1.received) != 1 || string(a1.received[0]) != "hello a" {
		t.Fatalf("expected a1 to receive the broadcast, got %v", a1.received)
	}
	if len(a2.received) != 1 || string(a2.received[0]) != "hello a" {
		t.Fatalf("expected a2 to receive the broadcast, got %v", a2.received)
	}
	if len(b1.received) != 0 {
		t.Fatalf("expected b1 (different room) to receive nothing, got %v", b1.received)
	}
}

func TestRegistry_LeaveStopsFurtherBroadcasts(t *testing.T) {
	r := NewRegistry()
	c := &fakeConn{}
	r.Join("/doc/a.md", c)
	r.Leave("/doc/a.md", c)

	r.Broadcast("/doc/a.md", []byte("after leave"))

	if len(c.received) != 0 {
		t.Fatalf("expected no payloads after Leave, got %v", c.received)
	}
}

func TestRegistry_LastPayloadSeedsLateJoiners(t *testing.T) {
	r := NewRegistry()

	if _, ok := r.LastPayload("/doc/a.md"); ok {
		t.Fatalf("expected no last payload before any broadcast")
	}

	r.Broadcast("/doc/a.md", []byte("current content"))

	payload, ok := r.LastPayload("/doc/a.md")
	if !ok {
		t.Fatalf("expected a last payload to be recorded")
	}
	if string(payload) != "current content" {
		t.Fatalf("expected %q, got %q", "current content", payload)
	}
}

func TestRegistry_BroadcastCollectsSendErrorsWithoutStoppingFanout(t *testing.T) {
	r := NewRegistry()
	failing := &fakeConn{failNext: true}
	healthy := &fakeConn{}
	r.Join("/doc/a.md", failing)
	r.Join("/doc/a.md", healthy)

	errs := r.Broadcast("/doc/a.md", []byte("payload"))

	if len(errs) != 1 {
		t.Fatalf("expected exactly 1 send error, got %d", len(errs))
	}
	if len(healthy.received) != 1 {
		t.Fatalf("expected healthy connection to still receive the payload despite the other's failure")
	}
}

func TestRegistry_BroadcastEphemeralReachesRoomWithoutTouchingLastPayload(t *testing.T) {
	r := NewRegistry()
	c := &fakeConn{}
	r.Join("/doc/a.md", c)

	r.Broadcast("/doc/a.md", []byte("real content"))
	r.BroadcastEphemeral("/doc/a.md", []byte("\x0142/100"))

	if len(c.received) != 2 {
		t.Fatalf("expected connection to receive both the content broadcast and the ephemeral one, got %v", c.received)
	}
	if string(c.received[1]) != "\x0142/100" {
		t.Fatalf("expected connection to receive the ephemeral payload, got %q", c.received[1])
	}

	payload, ok := r.LastPayload("/doc/a.md")
	if !ok {
		t.Fatalf("expected a last payload to still be recorded")
	}
	if string(payload) != "real content" {
		t.Fatalf("BroadcastEphemeral must not overwrite LastPayload; expected %q, got %q", "real content", payload)
	}
}

func TestRegistry_BroadcastEphemeralOnlyReachesSameRoom(t *testing.T) {
	r := NewRegistry()
	a1 := &fakeConn{}
	b1 := &fakeConn{}
	r.Join("/doc/a.md", a1)
	r.Join("/doc/b.md", b1)

	r.BroadcastEphemeral("/doc/a.md", []byte("\x015/10"))

	if len(a1.received) != 1 {
		t.Fatalf("expected a1 to receive the ephemeral broadcast, got %v", a1.received)
	}
	if len(b1.received) != 0 {
		t.Fatalf("expected b1 (different room) to receive nothing, got %v", b1.received)
	}
}

func TestRegistry_BroadcastAllEphemeralReachesEveryRoomWithoutTouchingLastPayload(t *testing.T) {
	r := NewRegistry()
	a1 := &fakeConn{}
	a2 := &fakeConn{}
	b1 := &fakeConn{}
	r.Join("/doc/a.md", a1)
	r.Join("/doc/a.md", a2)
	r.Join("/doc/b.md", b1)

	r.Broadcast("/doc/a.md", []byte("content a"))
	r.Broadcast("/doc/b.md", []byte("content b"))

	r.BroadcastAllEphemeral([]byte("\x02"))

	for name, c := range map[string]*fakeConn{"a1": a1, "a2": a2, "b1": b1} {
		if string(c.received[len(c.received)-1]) != "\x02" {
			t.Fatalf("expected %s to receive the global close signal last, got %v", name, c.received)
		}
	}

	// The global ephemeral must not overwrite any room's last content.
	if p, _ := r.LastPayload("/doc/a.md"); string(p) != "content a" {
		t.Fatalf("BroadcastAllEphemeral must not touch LastPayload; got %q", p)
	}
	if p, _ := r.LastPayload("/doc/b.md"); string(p) != "content b" {
		t.Fatalf("BroadcastAllEphemeral must not touch LastPayload; got %q", p)
	}
}

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

// Fence highlights are stored *alongside* the content, not instead of it: a
// reloaded tab is seeded with both, and getting this wrong would either lose
// the document (if spans overwrote it) or show it unhighlighted until the next
// edit (if spans were ephemeral).
func TestRegistry_BroadcastSpansSeedsLateJoinersWithoutReplacingContent(t *testing.T) {
	r := NewRegistry()

	if _, ok := r.LastSpans("/doc/a.md"); ok {
		t.Fatalf("expected no spans before any broadcast")
	}

	r.Broadcast("/doc/a.md", []byte("current content"))
	r.BroadcastSpans("/doc/a.md", []byte("current spans"))

	spans, ok := r.LastSpans("/doc/a.md")
	if !ok {
		t.Fatalf("expected spans to be recorded")
	}
	if string(spans) != "current spans" {
		t.Fatalf("expected %q, got %q", "current spans", spans)
	}

	content, ok := r.LastPayload("/doc/a.md")
	if !ok || string(content) != "current content" {
		t.Fatalf("BroadcastSpans must not touch LastPayload; got %q (ok=%v)", content, ok)
	}
}

func TestRegistry_BroadcastSpansOnlyReachesSameRoom(t *testing.T) {
	r := NewRegistry()
	a := &fakeConn{}
	b := &fakeConn{}
	r.Join("/doc/a.md", a)
	r.Join("/doc/b.md", b)

	r.BroadcastSpans("/doc/a.md", []byte("spans for a"))

	if len(a.received) != 1 || string(a.received[0]) != "spans for a" {
		t.Fatalf("expected the room's own connection to receive the spans, got %q", a.received)
	}
	if len(b.received) != 0 {
		t.Fatalf("expected another room to receive nothing, got %q", b.received)
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

func TestRegistry_DocDirUnrecordedBeforeSetDocDir(t *testing.T) {
	r := NewRegistry()
	if _, ok := r.DocDir("session-1"); ok {
		t.Fatalf("expected no doc dir before SetDocDir was ever called")
	}
}

func TestRegistry_SetDocDirRecordsPerKey(t *testing.T) {
	r := NewRegistry()
	r.SetDocDir("session-1", "/docs/a")
	r.SetDocDir("session-2", "/docs/b")

	dir, ok := r.DocDir("session-1")
	if !ok || dir != "/docs/a" {
		t.Fatalf("expected session-1 -> /docs/a, got %q (ok=%v)", dir, ok)
	}
	dir, ok = r.DocDir("session-2")
	if !ok || dir != "/docs/b" {
		t.Fatalf("expected session-2 -> /docs/b, got %q (ok=%v)", dir, ok)
	}
}

func TestRegistry_SetDocDirOverwritesOnDocumentSwitch(t *testing.T) {
	r := NewRegistry()
	r.SetDocDir("session-1", "/docs/a")
	r.SetDocDir("session-1", "/docs/c")

	dir, ok := r.DocDir("session-1")
	if !ok || dir != "/docs/c" {
		t.Fatalf("expected the later SetDocDir to win, got %q (ok=%v)", dir, ok)
	}
}

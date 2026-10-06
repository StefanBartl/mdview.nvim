package relay

import (
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"
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

// The spotlight state belongs to the editor, not to a document: it reaches
// every room, and a tab that joins later is seeded with the latest one.
func TestRegistry_BroadcastSpotlightReachesEveryRoom(t *testing.T) {
	r := NewRegistry()
	a := &fakeConn{}
	b := &fakeConn{}
	r.Join("/doc/a.md", a)
	r.Join("/doc/b.md", b)

	r.BroadcastSpotlight([]byte("state"))

	if len(a.received) != 1 || string(a.received[0]) != "state" {
		t.Fatalf("expected room a to receive the state, got %q", a.received)
	}
	if len(b.received) != 1 || string(b.received[0]) != "state" {
		t.Fatalf("expected room b to receive the state, got %q", b.received)
	}
}

func TestRegistry_BroadcastSpotlightIsStoredAndKeepsOnlyTheLatest(t *testing.T) {
	r := NewRegistry()

	if _, ok := r.LastSpotlight(); ok {
		t.Fatalf("expected no spotlight state before any broadcast")
	}

	r.Broadcast("/doc/a.md", []byte("content"))
	r.BroadcastSpotlight([]byte("first"))
	r.BroadcastSpotlight([]byte("second"))

	state, ok := r.LastSpotlight()
	if !ok || string(state) != "second" {
		t.Fatalf("expected the latest state %q, got %q (ok=%v)", "second", state, ok)
	}
	content, ok := r.LastPayload("/doc/a.md")
	if !ok || string(content) != "content" {
		t.Fatalf("BroadcastSpotlight must not touch the content; got %q (ok=%v)", content, ok)
	}
}

// slowConn blocks its first Send until released, to hold a seed "on the wire"
// while a broadcast arrives. It records payloads in delivery order.
type slowConn struct {
	mu       sync.Mutex
	received []string
	entered  chan struct{} // closed when the first Send has started
	release  chan struct{} // the first Send waits for this
	once     sync.Once
}

func newSlowConn() *slowConn {
	return &slowConn{entered: make(chan struct{}), release: make(chan struct{})}
}

func (s *slowConn) Send(payload []byte) error {
	first := false
	s.once.Do(func() { first = true })
	if first {
		close(s.entered)
		<-s.release
	}
	s.mu.Lock()
	s.received = append(s.received, string(payload))
	s.mu.Unlock()
	return nil
}

func (s *slowConn) got() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.received...)
}

func TestRegistry_JoinAndSeedDeliversContentSpansThenSpotlight(t *testing.T) {
	r := NewRegistry()
	r.Broadcast("/doc/a.md", []byte("content"))
	r.BroadcastSpans("/doc/a.md", []byte("spans"))
	r.BroadcastSpotlight([]byte("spotlight"))

	c := &fakeConn{}
	if err := r.JoinAndSeed("/doc/a.md", c); err != nil {
		t.Fatalf("JoinAndSeed: %v", err)
	}

	want := []string{"content", "spans", "spotlight"}
	if len(c.received) != len(want) {
		t.Fatalf("expected %v, got %q", want, c.received)
	}
	for i, w := range want {
		if string(c.received[i]) != w {
			t.Fatalf("seed %d: expected %q, got %q", i, w, c.received[i])
		}
	}

	// Joined for good: the next broadcast arrives too.
	r.Broadcast("/doc/a.md", []byte("next"))
	if string(c.received[len(c.received)-1]) != "next" {
		t.Fatalf("expected the joined connection to receive later broadcasts, got %q", c.received)
	}
}

func TestRegistry_JoinAndSeedSendsNothingWhenThereIsNoState(t *testing.T) {
	r := NewRegistry()
	c := &fakeConn{}
	if err := r.JoinAndSeed("/doc/a.md", c); err != nil {
		t.Fatalf("JoinAndSeed: %v", err)
	}
	if len(c.received) != 0 {
		t.Fatalf("expected no seed, got %q", c.received)
	}
}

func TestRegistry_JoinAndSeedReportsASendError(t *testing.T) {
	r := NewRegistry()
	r.Broadcast("/doc/a.md", []byte("content"))
	c := &fakeConn{failNext: true}
	if err := r.JoinAndSeed("/doc/a.md", c); err == nil {
		t.Fatalf("expected the send error to be returned")
	}
}

// The race this guards: Join, then LastPayload (old state read), then a
// broadcast that reaches the connection, then the old state is sent after it.
// With the seed held on the wire, a broadcast issued after the join must wait
// for it and arrive second.
func TestRegistry_BroadcastAfterJoinNeverOvertakesTheSeed(t *testing.T) {
	cases := []struct {
		name      string
		store     func(r *Registry)
		broadcast func(r *Registry)
		old, new  string
	}{
		{
			name:      "content",
			store:     func(r *Registry) { r.Broadcast("/doc/a.md", []byte("old")) },
			broadcast: func(r *Registry) { r.Broadcast("/doc/a.md", []byte("fresh")) },
			old:       "old", new: "fresh",
		},
		{
			name:      "spans",
			store:     func(r *Registry) { r.BroadcastSpans("/doc/a.md", []byte("old")) },
			broadcast: func(r *Registry) { r.BroadcastSpans("/doc/a.md", []byte("fresh")) },
			old:       "old", new: "fresh",
		},
		{
			name:      "spotlight",
			store:     func(r *Registry) { r.BroadcastSpotlight([]byte("old")) },
			broadcast: func(r *Registry) { r.BroadcastSpotlight([]byte("fresh")) },
			old:       "old", new: "fresh",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := NewRegistry()
			tc.store(r)

			c := newSlowConn()
			joined := make(chan error, 1)
			go func() { joined <- r.JoinAndSeed("/doc/a.md", c) }()
			<-c.entered // the old state is on the wire, the connection is registered

			broadcast := make(chan struct{})
			go func() {
				tc.broadcast(r)
				close(broadcast)
			}()

			// The broadcast must be held back while the seed is in flight.
			select {
			case <-broadcast:
				t.Fatalf("a broadcast overtook the seed that was still being delivered")
			case <-time.After(50 * time.Millisecond):
			}

			close(c.release)
			if err := <-joined; err != nil {
				t.Fatalf("JoinAndSeed: %v", err)
			}
			<-broadcast

			got := c.got()
			if len(got) != 2 || got[0] != tc.old || got[1] != tc.new {
				t.Fatalf("expected [%s %s] in that order, got %q", tc.old, tc.new, got)
			}
		})
	}
}

func TestRegistry_ConcurrentJoinsAndBroadcastsEndOnTheLatestState(t *testing.T) {
	r := NewRegistry()
	r.Broadcast("/doc/a.md", []byte("v0"))

	const joiners = 20
	conns := make([]*recordingConn, joiners)
	var wg sync.WaitGroup
	for i := range conns {
		conns[i] = &recordingConn{}
		wg.Add(1)
		go func(c *recordingConn) {
			defer wg.Done()
			_ = r.JoinAndSeed("/doc/a.md", c)
		}(conns[i])
	}
	for v := 1; v <= 50; v++ {
		r.Broadcast("/doc/a.md", []byte(fmt.Sprintf("v%d", v)))
	}
	wg.Wait()
	r.Broadcast("/doc/a.md", []byte("final"))

	for i, c := range conns {
		got := c.got()
		if len(got) == 0 || got[len(got)-1] != "final" {
			t.Fatalf("conn %d did not end on the latest state: %q", i, got)
		}
		// Versions never go backwards on a connection.
		last := -1
		for _, p := range got {
			var n int
			if _, err := fmt.Sscanf(p, "v%d", &n); err != nil {
				continue
			}
			if n < last {
				t.Fatalf("conn %d saw v%d after v%d: %q", i, n, last, got)
			}
			last = n
		}
	}
}

// recordingConn is a fakeConn that is safe for the concurrent test above.
type recordingConn struct {
	mu       sync.Mutex
	received []string
}

func (c *recordingConn) Send(payload []byte) error {
	c.mu.Lock()
	c.received = append(c.received, string(payload))
	c.mu.Unlock()
	return nil
}

func (c *recordingConn) got() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]string(nil), c.received...)
}

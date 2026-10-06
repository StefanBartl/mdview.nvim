package source

import (
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

// fakeBroadcaster records every (key, payload) pair, so tests can assert what
// the watcher would have pushed to a room without a registry or a network.
type fakeBroadcaster struct {
	mu       sync.Mutex
	keys     []string
	payloads [][]byte
}

func (f *fakeBroadcaster) Broadcast(key string, payload []byte) []error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.keys = append(f.keys, key)
	f.payloads = append(f.payloads, append([]byte(nil), payload...))
	return nil
}

func (f *fakeBroadcaster) snapshot() ([]string, [][]byte) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.keys...), append([][]byte(nil), f.payloads...)
}

// waitFor polls cond until it holds or the deadline passes, so timing-dependent
// assertions don't need a fixed sleep long enough for the slowest CI runner.
func waitFor(t *testing.T, cond func() bool) bool {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return true
		}
		time.Sleep(5 * time.Millisecond)
	}
	return false
}

func TestWatch_BroadcastsInitialContentImmediately(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "doc.md")
	if err := os.WriteFile(path, []byte("# hello"), 0o644); err != nil {
		t.Fatal(err)
	}

	b := &fakeBroadcaster{}
	stop := make(chan struct{})
	defer close(stop)
	go Watch(b, "room", path, 10*time.Millisecond, stop)

	if !waitFor(t, func() bool { _, p := b.snapshot(); return len(p) >= 1 }) {
		t.Fatal("expected an immediate broadcast of the file's initial content")
	}
	keys, payloads := b.snapshot()
	if keys[0] != "room" {
		t.Fatalf("expected broadcast to room %q, got %q", "room", keys[0])
	}
	if string(payloads[0]) != "# hello" {
		t.Fatalf("expected initial content %q, got %q", "# hello", payloads[0])
	}
}

func TestWatch_BroadcastsOnChange(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "doc.md")
	if err := os.WriteFile(path, []byte("one"), 0o644); err != nil {
		t.Fatal(err)
	}

	b := &fakeBroadcaster{}
	stop := make(chan struct{})
	defer close(stop)
	go Watch(b, "room", path, 10*time.Millisecond, stop)

	if !waitFor(t, func() bool { _, p := b.snapshot(); return len(p) >= 1 }) {
		t.Fatal("initial broadcast never arrived")
	}
	if err := os.WriteFile(path, []byte("two"), 0o644); err != nil {
		t.Fatal(err)
	}

	if !waitFor(t, func() bool {
		_, p := b.snapshot()
		return len(p) >= 2 && string(p[len(p)-1]) == "two"
	}) {
		t.Fatal("expected the changed content to be broadcast")
	}
}

// A no-op save (same bytes) must not trigger a re-render — the watcher compares
// content rather than mtime precisely so this case stays quiet.
func TestWatch_IgnoresRewriteWithIdenticalContent(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "doc.md")
	if err := os.WriteFile(path, []byte("same"), 0o644); err != nil {
		t.Fatal(err)
	}

	b := &fakeBroadcaster{}
	stop := make(chan struct{})
	defer close(stop)
	go Watch(b, "room", path, 10*time.Millisecond, stop)

	if !waitFor(t, func() bool { _, p := b.snapshot(); return len(p) >= 1 }) {
		t.Fatal("initial broadcast never arrived")
	}
	for i := 0; i < 3; i++ {
		if err := os.WriteFile(path, []byte("same"), 0o644); err != nil {
			t.Fatal(err)
		}
		time.Sleep(20 * time.Millisecond)
	}

	_, payloads := b.snapshot()
	if len(payloads) != 1 {
		t.Fatalf("expected exactly 1 broadcast for unchanged content, got %d", len(payloads))
	}
}

// A vanished file (the window during an editor's write-temp-then-rename) must
// not kill the watcher — it has to recover once the file is back.
func TestWatch_SurvivesTemporarilyMissingFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "doc.md")
	if err := os.WriteFile(path, []byte("before"), 0o644); err != nil {
		t.Fatal(err)
	}

	b := &fakeBroadcaster{}
	stop := make(chan struct{})
	defer close(stop)
	go Watch(b, "room", path, 10*time.Millisecond, stop)

	if !waitFor(t, func() bool { _, p := b.snapshot(); return len(p) >= 1 }) {
		t.Fatal("initial broadcast never arrived")
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	time.Sleep(30 * time.Millisecond)
	if err := os.WriteFile(path, []byte("after"), 0o644); err != nil {
		t.Fatal(err)
	}

	if !waitFor(t, func() bool {
		_, p := b.snapshot()
		return len(p) >= 2 && string(p[len(p)-1]) == "after"
	}) {
		t.Fatal("watcher did not recover after the file reappeared")
	}
}

func TestWatch_StopsWhenStopChannelClosed(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "doc.md")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	b := &fakeBroadcaster{}
	stop := make(chan struct{})
	done := make(chan struct{})
	go func() {
		Watch(b, "room", path, 10*time.Millisecond, stop)
		close(done)
	}()

	if !waitFor(t, func() bool { _, p := b.snapshot(); return len(p) >= 1 }) {
		t.Fatal("initial broadcast never arrived")
	}
	close(stop)

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Watch did not return after stop was closed")
	}
}

// scripted hands out the scripted reads one per poll (the last one
// repeats), so a test drives the debounce poll by poll without a clock or a
// file system.
type scriptedRead struct {
	content string
	err     error
}

func scripted(reads ...scriptedRead) func(string) ([]byte, error) {
	i := 0
	return func(string) ([]byte, error) {
		r := reads[i]
		if i < len(reads)-1 {
			i++
		}
		if r.err != nil {
			return nil, r.err
		}
		if r.content == "" {
			return nil, nil // deliberately nil: an empty file must not depend on a non-nil slice
		}
		return []byte(r.content), nil
	}
}

func newScripted(reads ...scriptedRead) (*watcher, *fakeBroadcaster) {
	b := &fakeBroadcaster{}
	return &watcher{b: b, key: "room", path: "doc.md", read: scripted(reads...)}, b
}

func contents(b *fakeBroadcaster) []string {
	_, p := b.snapshot()
	out := make([]string, len(p))
	for i, c := range p {
		out[i] = string(c)
	}
	return out
}

func expectSent(t *testing.T, b *fakeBroadcaster, want ...string) {
	t.Helper()
	got := contents(b)
	if len(got) != len(want) {
		t.Fatalf("broadcasts = %q, want %q", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("broadcasts = %q, want %q", got, want)
		}
	}
}

func TestPoll_FirstNonEmptyReadIsBroadcastAtOnce(t *testing.T) {
	w, b := newScripted(scriptedRead{content: "hello"})
	w.poll()
	expectSent(t, b, "hello")
	w.poll()
	expectSent(t, b, "hello")
}

// The very first read can land in the truncate window of a non-atomic save: it
// must not be broadcast as an empty preview, the real content that follows is.
func TestPoll_EmptyFirstReadIsHeldBackUntilConfirmed(t *testing.T) {
	w, b := newScripted(scriptedRead{content: ""}, scriptedRead{content: "full"})
	w.poll()
	expectSent(t, b)
	w.poll()
	expectSent(t, b, "full")
}

// An intentionally empty file is real content: broadcast once it reads empty
// on a second poll.
func TestPoll_StableEmptyFirstReadIsBroadcastOnSecondPoll(t *testing.T) {
	w, b := newScripted(scriptedRead{content: ""})
	w.poll()
	expectSent(t, b)
	w.poll()
	expectSent(t, b, "")
	w.poll()
	expectSent(t, b, "")
}

func TestPoll_ChangeNeedsTwoEqualReads(t *testing.T) {
	w, b := newScripted(
		scriptedRead{content: "one"},
		scriptedRead{content: "tw"}, // partial write
		scriptedRead{content: "two"},
		scriptedRead{content: "two"},
	)
	w.poll()
	w.poll()
	w.poll()
	expectSent(t, b, "one")
	w.poll()
	expectSent(t, b, "one", "two")
}

// Truncate-then-write between two polls leaves an empty read in the middle.
func TestPoll_TransientEmptyIsNeverBroadcast(t *testing.T) {
	w, b := newScripted(
		scriptedRead{content: "full"},
		scriptedRead{content: ""},
		scriptedRead{content: "full2"},
		scriptedRead{content: "full2"},
	)
	for i := 0; i < 4; i++ {
		w.poll()
	}
	expectSent(t, b, "full", "full2")
}

func TestPoll_EmptiedFileThatStaysEmptyIsBroadcast(t *testing.T) {
	w, b := newScripted(scriptedRead{content: "full"}, scriptedRead{content: ""})
	w.poll()
	w.poll()
	expectSent(t, b, "full")
	w.poll()
	expectSent(t, b, "full", "")
}

// A revert to the broadcast content cancels the pending candidate.
func TestPoll_RevertCancelsPending(t *testing.T) {
	w, b := newScripted(
		scriptedRead{content: "a"},
		scriptedRead{content: "b"},
		scriptedRead{content: "a"},
		scriptedRead{content: "b"},
	)
	for i := 0; i < 4; i++ {
		w.poll()
	}
	expectSent(t, b, "a")
}

func TestPoll_ReadErrorsAreSurvivedAndRecovered(t *testing.T) {
	gone := errors.New("gone")
	w, b := newScripted(
		scriptedRead{content: "before"},
		scriptedRead{err: gone},
		scriptedRead{err: gone},
		scriptedRead{content: "after"},
		scriptedRead{content: "after"},
	)
	for i := 0; i < 5; i++ {
		w.poll()
	}
	expectSent(t, b, "before", "after")
	if w.reportedErr {
		t.Fatal("the error state should be cleared once the file is readable again")
	}
}

// run feeds poll from a tick channel and returns on stop; an unbuffered tick
// channel makes every send a rendezvous, so no sleeping is involved.
func TestRun_PollsOnEveryTickAndStopsOnStop(t *testing.T) {
	w, b := newScripted(scriptedRead{content: "one"}, scriptedRead{content: "two"})
	tick := make(chan time.Time)
	stop := make(chan struct{})
	done := make(chan struct{})
	go func() {
		w.run(tick, stop)
		close(done)
	}()

	tick <- time.Time{} // "one", first read: sent at once
	tick <- time.Time{} // "two" seen once: held back
	tick <- time.Time{} // "two" again: sent
	// The next send returns only after the loop finished the previous poll.
	tick <- time.Time{}
	expectSent(t, b, "one", "two")

	close(stop)
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("run did not return after stop was closed")
	}
}

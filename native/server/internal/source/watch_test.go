package source

import (
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

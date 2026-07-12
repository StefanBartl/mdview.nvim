package relay

import "testing"

func TestNavQueue_PushDrainIsFIFOAndEmptiesQueue(t *testing.T) {
	q := NewNavQueue()
	if got := q.Drain(); got != nil {
		t.Fatalf("expected nil from empty queue, got %v", got)
	}

	q.Push(NavRequest{Key: "/doc/a.md", Href: "b.md"})
	q.Push(NavRequest{Key: "/doc/a.md", Href: "sub/c.md"})

	out := q.Drain()
	if len(out) != 2 || out[0].Href != "b.md" || out[1].Href != "sub/c.md" {
		t.Fatalf("expected FIFO [b.md, sub/c.md], got %v", out)
	}
	if again := q.Drain(); again != nil {
		t.Fatalf("expected queue emptied after drain, got %v", again)
	}
}

func TestNavQueue_DropsOldestAtCapacity(t *testing.T) {
	q := NewNavQueue()
	for i := 0; i < maxNavQueue+10; i++ {
		q.Push(NavRequest{Key: "/doc/a.md", Href: "x"})
	}
	if got := len(q.Drain()); got != maxNavQueue {
		t.Fatalf("expected queue capped at %d, got %d", maxNavQueue, got)
	}
}

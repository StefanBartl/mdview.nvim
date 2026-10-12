package relay

import (
	"strings"
	"testing"
)

func TestEditQueue_DrainIsFIFOAndEmpties(t *testing.T) {
	q := NewEditQueue()
	q.Push(EditRequest{Key: "k", Start: 1, End: 1, Expected: "a", Text: "b"})
	q.Push(EditRequest{Key: "k", Start: 2, End: 2, Expected: "c", Text: "d"})

	got := q.Drain()
	if len(got) != 2 || got[0].Start != 1 || got[1].Start != 2 {
		t.Fatalf("drained = %+v", got)
	}
	if again := q.Drain(); again != nil {
		t.Fatalf("second drain = %+v, want nil", again)
	}
}

func TestEditQueue_DropsTheOldestAtTheCountLimit(t *testing.T) {
	q := NewEditQueue()
	for i := 1; i <= maxEditQueue+5; i++ {
		q.Push(EditRequest{Key: "k", Start: i, End: i})
	}
	got := q.Drain()
	if len(got) != maxEditQueue {
		t.Fatalf("len = %d, want %d", len(got), maxEditQueue)
	}
	if got[0].Start != 6 {
		t.Fatalf("oldest kept = %d, want 6", got[0].Start)
	}
}

func TestEditQueue_DropsTheOldestAtTheByteLimit(t *testing.T) {
	q := NewEditQueue()
	big := strings.Repeat("x", maxEditQueueBytes/4+1)
	for i := 1; i <= 6; i++ {
		q.Push(EditRequest{Key: "k", Start: i, End: i, Text: big})
	}
	got := q.Drain()
	total := 0
	for _, r := range got {
		total += r.size()
	}
	if total > maxEditQueueBytes {
		t.Fatalf("queue holds %d bytes, over the %d budget", total, maxEditQueueBytes)
	}
	if got[len(got)-1].Start != 6 {
		t.Fatalf("newest edit was dropped: %+v", got)
	}
}

func TestEditQueue_ByteCountResetsAfterDrain(t *testing.T) {
	q := NewEditQueue()
	big := strings.Repeat("x", maxEditQueueBytes/2)
	q.Push(EditRequest{Key: "k", Start: 1, End: 1, Text: big})
	q.Drain()
	q.Push(EditRequest{Key: "k", Start: 2, End: 2, Text: big})
	q.Push(EditRequest{Key: "k", Start: 3, End: 3, Text: "small"})
	if got := q.Drain(); len(got) != 2 {
		t.Fatalf("len = %d, want 2 (the budget must not remember drained bytes)", len(got))
	}
}

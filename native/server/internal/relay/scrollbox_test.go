package relay

import "testing"

func TestScrollBox_SetKeepsOnlyLatestAndTakeConsumes(t *testing.T) {
	b := NewScrollBox()
	if got := b.Take(); got != nil {
		t.Fatalf("expected nil from empty box, got %v", got)
	}

	b.Set(ScrollHint{Key: "/doc/a.md", Ratio: 0.2})
	b.Set(ScrollHint{Key: "/doc/a.md", Ratio: 0.8}) // supersedes

	got := b.Take()
	if got == nil || got.Ratio != 0.8 || got.Key != "/doc/a.md" {
		t.Fatalf("expected latest hint {a.md,0.8}, got %v", got)
	}
	if again := b.Take(); again != nil {
		t.Fatalf("expected box emptied after Take, got %v", again)
	}
}

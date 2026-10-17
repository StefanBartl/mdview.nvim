package relay

import (
	"testing"
	"time"
)

func TestClients_NilMeansEverythingIsMine(t *testing.T) {
	var c *Clients
	if !c.Mine("a", "room") || !c.Mine("", "room") {
		t.Fatal("an unshared relay must hand every room to every poller")
	}
	if st := c.Status(nil); st.Shared || st.Protocol != SharedProtocol {
		t.Fatalf("status of an unshared relay = %+v", st)
	}
}

func TestClients_OwnerGetsTheRoom(t *testing.T) {
	c := NewClients()
	c.SetOwner("room", "a")
	if !c.Mine("a", "room") {
		t.Fatal("owner a must get its room")
	}
	if c.Mine("b", "room") {
		t.Fatal("b must not get a room a owns")
	}
	if !c.Mine("b", "other") {
		t.Fatal("a room nobody owns goes to whoever polls")
	}
	if !c.Mine("", "room") {
		t.Fatal("an anonymous poller drains everything (unshared behavior)")
	}
	c.SetOwner("room", "b")
	if c.Mine("a", "room") || !c.Mine("b", "room") {
		t.Fatal("the last instance to push owns the room")
	}
}

func TestClients_DetachDropsOwnership(t *testing.T) {
	c := NewClients()
	now := time.Now()
	c.Touch("a", now)
	c.Touch("b", now)
	c.SetOwner("room", "a")
	if left := c.Detach("a"); left != 1 {
		t.Fatalf("left = %d, want 1", left)
	}
	if _, ok := c.Owner("room"); ok {
		t.Fatal("a detached instance must not keep owning a room")
	}
}

func TestClients_PruneForgetsSilentInstances(t *testing.T) {
	c := NewClients()
	now := time.Now()
	c.Touch("a", now.Add(-time.Minute))
	c.Touch("b", now)
	c.SetOwner("room", "a")
	if left := c.Prune(now, 30*time.Second); left != 1 {
		t.Fatalf("left = %d, want 1", left)
	}
	if _, ok := c.Owner("room"); ok {
		t.Fatal("a pruned instance must not keep owning a room")
	}
	c.Refresh(now.Add(time.Hour))
	if left := c.Prune(now.Add(time.Hour), 30*time.Second); left != 1 {
		t.Fatal("Refresh must count as a heartbeat of every attached instance")
	}
}

func TestQueues_DrainForLeavesOtherRoomsQueued(t *testing.T) {
	q := NewToggleQueue()
	q.Push(ToggleRequest{Key: "a.md", Line: 1})
	q.Push(ToggleRequest{Key: "b.md", Line: 2})
	q.Push(ToggleRequest{Key: "a.md", Line: 3})
	got := q.DrainFor(func(k string) bool { return k == "a.md" })
	if len(got) != 2 || got[0].Line != 1 || got[1].Line != 3 {
		t.Fatalf("taken = %+v", got)
	}
	rest := q.Drain()
	if len(rest) != 1 || rest[0].Key != "b.md" {
		t.Fatalf("left = %+v", rest)
	}

	e := NewEditQueue()
	e.Push(EditRequest{Key: "a.md", Text: "xx"})
	e.Push(EditRequest{Key: "b.md", Text: "yyyy"})
	e.DrainFor(func(k string) bool { return k == "a.md" })
	if e.bytes != (EditRequest{Key: "b.md", Text: "yyyy"}).size() {
		t.Fatalf("byte budget = %d after a partial drain", e.bytes)
	}

	b := NewScrollBox()
	b.Set(ScrollHint{Key: "b.md", Ratio: 0.5})
	if h := b.TakeFor(func(k string) bool { return k == "a.md" }); h != nil {
		t.Fatal("a scroll hint of another room must stay for its owner")
	}
	if h := b.TakeFor(func(k string) bool { return k == "b.md" }); h == nil || h.Ratio != 0.5 {
		t.Fatalf("owner did not get its hint: %+v", h)
	}
}

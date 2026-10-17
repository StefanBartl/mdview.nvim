package relay

import (
	"sort"
	"sync"
	"time"
)

// SharedProtocol is the version of the shared-relay contract (/attach,
// /detach, the `client` query parameter and the discovery file). A Neovim
// instance only attaches to a relay that reports the protocol it speaks, so
// two plugin versions at one relay fail loudly instead of half-working.
const SharedProtocol = 1

// Clients tracks the Neovim instances attached to a shared relay
// (`--shared`): when each was last heard from, and which instance owns each
// room, i.e. pushed what the tab of that room shows right now.
//
// Ownership is what routes the browser's write-backs (checkbox, text field,
// block edit, click-to-navigate, reverse scroll): the queues are shared, but an
// instance that names itself when it drains them only gets the requests of the
// rooms it owns. The last instance to push content or a document into a room
// owns it -- that is the instance with the focus, since only it pushes.
//
// A nil *Clients is valid and means "not shared": every room belongs to
// everybody, which is the behavior of a relay with a single Neovim instance.
type Clients struct {
	mu     sync.Mutex
	seen   map[string]time.Time
	owners map[string]string
	ever   bool
}

func NewClients() *Clients {
	return &Clients{
		seen:   make(map[string]time.Time),
		owners: make(map[string]string),
	}
}

// Touch records that instance id is alive at now (every request that names a
// client counts as a heartbeat).
func (c *Clients) Touch(id string, now time.Time) {
	if c == nil || id == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.seen[id] = now
	c.ever = true
}

// Detach forgets instance id and every room it owned (their write-backs then go
// to whichever instance polls first, as on an unshared relay). Returns how many
// instances are still attached.
func (c *Clients) Detach(id string) int {
	if c == nil {
		return 0
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.dropLocked(id)
	return len(c.seen)
}

func (c *Clients) dropLocked(id string) {
	delete(c.seen, id)
	for room, owner := range c.owners {
		if owner == id {
			delete(c.owners, room)
		}
	}
}

// SetOwner makes instance id the owner of room.
func (c *Clients) SetOwner(room, id string) {
	if c == nil || room == "" || id == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.owners[room] = id
}

// Owner returns the instance owning room, if any.
func (c *Clients) Owner(room string) (string, bool) {
	if c == nil {
		return "", false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	id, ok := c.owners[room]
	return id, ok
}

// Mine reports whether a write-back for room belongs to instance id: always
// for an anonymous poller (id == "") and for a room nobody owns, else only for
// the owner.
func (c *Clients) Mine(id, room string) bool {
	if c == nil || id == "" {
		return true
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	owner, ok := c.owners[room]
	return !ok || owner == id
}

// Prune forgets every instance not heard from within timeout and returns how
// many are left.
func (c *Clients) Prune(now time.Time, timeout time.Duration) int {
	if c == nil {
		return 0
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	for id, at := range c.seen {
		if now.Sub(at) > timeout {
			c.dropLocked(id)
		}
	}
	return len(c.seen)
}

// Refresh marks every attached instance as heard from at now. Used after the
// machine slept: nobody could send a heartbeat meanwhile, which says nothing
// about whether they are still there.
func (c *Clients) Refresh(now time.Time) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	for id := range c.seen {
		c.seen[id] = now
	}
}

// Status is what /attach answers: the protocol, how many instances are
// attached, who owns which room, and the rooms that have a tab connected (so an
// instance that attaches can follow the tab that is already open instead of
// opening a second one).
type Status struct {
	Protocol int               `json:"protocol"`
	Shared   bool              `json:"shared"`
	Clients  int               `json:"clients"`
	Owners   map[string]string `json:"owners"`
	Tabs     []string          `json:"tabs"`
}

// Status snapshots the attachment state; tabs is passed in (the registry knows
// the rooms) and sorted so the answer is deterministic.
func (c *Clients) Status(tabs []string) Status {
	sort.Strings(tabs)
	if tabs == nil {
		tabs = []string{}
	}
	st := Status{Protocol: SharedProtocol, Shared: c != nil, Owners: map[string]string{}, Tabs: tabs}
	if c == nil {
		return st
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	st.Clients = len(c.seen)
	for room, id := range c.owners {
		st.Owners[room] = id
	}
	return st
}

// EverAttached reports whether any instance has attached since the relay
// started (until then the relay waits longer before it gives up).
func (c *Clients) EverAttached() bool {
	if c == nil {
		return false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.ever
}

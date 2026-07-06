package relay

import "sync"

// Conn is the minimal capability a room member needs. The production
// implementation wraps a WebSocket connection; tests use a fake so room
// logic can be verified without a network round trip.
type Conn interface {
	Send(payload []byte) error
}

// Registry groups connections into per-document "rooms" keyed by an
// arbitrary document key (the buffer's absolute path). Broadcasting a
// document update only reaches connections joined to that same key, which
// is what keeps multiple open files from cross-contaminating each other's
// preview tab.
type Registry struct {
	mu    sync.Mutex
	rooms map[string]map[Conn]struct{}
	last  map[string][]byte
}

func NewRegistry() *Registry {
	return &Registry{
		rooms: make(map[string]map[Conn]struct{}),
		last:  make(map[string][]byte),
	}
}

// Join adds c to the room for key. Call LastPayload afterwards to seed a
// newly-joined connection with the current content.
func (r *Registry) Join(key string, c Conn) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.rooms[key] == nil {
		r.rooms[key] = make(map[Conn]struct{})
	}
	r.rooms[key][c] = struct{}{}
}

// Leave removes c from the room for key. Safe to call even if c was never
// joined or the room no longer exists.
func (r *Registry) Leave(key string, c Conn) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.rooms[key], c)
}

// LastPayload returns the most recently broadcast payload for key, if any.
func (r *Registry) LastPayload(key string) ([]byte, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	payload, ok := r.last[key]
	return payload, ok
}

// Broadcast stores payload as the latest content for key and sends it to
// every connection currently joined to that key. Connections in other rooms
// never receive it. Send errors are collected and returned rather than
// aborting the fan-out, so one broken client cannot block delivery to
// the rest of the room.
func (r *Registry) Broadcast(key string, payload []byte) []error {
	r.mu.Lock()
	r.last[key] = payload
	conns := make([]Conn, 0, len(r.rooms[key]))
	for c := range r.rooms[key] {
		conns = append(conns, c)
	}
	r.mu.Unlock()

	var errs []error
	for _, c := range conns {
		if err := c.Send(payload); err != nil {
			errs = append(errs, err)
		}
	}
	return errs
}

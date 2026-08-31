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
	mu      sync.Mutex
	rooms   map[string]map[Conn]struct{}
	last    map[string][]byte
	spans   map[string][]byte
	docDirs map[string]string
}

func NewRegistry() *Registry {
	return &Registry{
		rooms:   make(map[string]map[Conn]struct{}),
		last:    make(map[string][]byte),
		spans:   make(map[string][]byte),
		docDirs: make(map[string]string),
	}
}

// SetDocDir records dir as the directory of the document currently previewed
// in key's room, so /asset can resolve a relative image path against it.
// Called from handleDoc, whose body (the previewed document's absolute path)
// comes only from the trusted local Neovim process — never from a browser
// tab, which only ever supplies the relative `path` query param to /asset.
func (r *Registry) SetDocDir(key, dir string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.docDirs[key] = dir
}

// DocDir returns the directory recorded by SetDocDir for key, if any.
func (r *Registry) DocDir(key string) (string, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	dir, ok := r.docDirs[key]
	return dir, ok
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

// LastSpans returns the most recently broadcast fence-highlight payload for
// key, if any.
func (r *Registry) LastSpans(key string) ([]byte, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	payload, ok := r.spans[key]
	return payload, ok
}

// BroadcastSpans fans a fence-highlight payload out to key's room and stores it
// as the room's latest, alongside — not instead of — the content in LastPayload.
//
// Stored rather than ephemeral because it describes the *current* document
// rather than a passing event: a tab that reloads is seeded with the content
// from LastPayload, and without this it would show that content unhighlighted
// until the next edit happened to arrive.
func (r *Registry) BroadcastSpans(key string, payload []byte) []error {
	r.mu.Lock()
	r.spans[key] = payload
	conns := r.connsForLocked(key)
	r.mu.Unlock()

	return sendAll(conns, payload)
}

// Broadcast stores payload as the latest content for key and sends it to
// every connection currently joined to that key. Connections in other rooms
// never receive it. Send errors are collected and returned rather than
// aborting the fan-out, so one broken client cannot block delivery to
// the rest of the room.
func (r *Registry) Broadcast(key string, payload []byte) []error {
	r.mu.Lock()
	r.last[key] = payload
	conns := r.connsForLocked(key)
	r.mu.Unlock()

	return sendAll(conns, payload)
}

// BroadcastEphemeral fans payload out to key's room exactly like Broadcast,
// but does NOT record it as the room's "last content" — for transient
// signals (e.g. cursor/scroll position) that a newly-joined connection
// should not be seeded with in place of the actual document content.
func (r *Registry) BroadcastEphemeral(key string, payload []byte) []error {
	r.mu.Lock()
	conns := r.connsForLocked(key)
	r.mu.Unlock()

	return sendAll(conns, payload)
}

// BroadcastAllEphemeral sends payload to every connection in every room,
// without recording it as any room's "last content". Used for global transient
// signals that aren't tied to one document — e.g. a "close now" ping sent to
// all preview tabs when the session stops. Like BroadcastEphemeral, a
// newly-joined connection is never seeded with it.
func (r *Registry) BroadcastAllEphemeral(payload []byte) []error {
	r.mu.Lock()
	var conns []Conn
	for key := range r.rooms {
		conns = append(conns, r.connsForLocked(key)...)
	}
	r.mu.Unlock()

	return sendAll(conns, payload)
}

// connsForLocked snapshots the current members of key's room. Caller must
// hold r.mu.
func (r *Registry) connsForLocked(key string) []Conn {
	conns := make([]Conn, 0, len(r.rooms[key]))
	for c := range r.rooms[key] {
		conns = append(conns, c)
	}
	return conns
}

func sendAll(conns []Conn, payload []byte) []error {
	var errs []error
	for _, c := range conns {
		if err := c.Send(payload); err != nil {
			errs = append(errs, err)
		}
	}
	return errs
}

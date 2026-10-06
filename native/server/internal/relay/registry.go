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
	mu        sync.Mutex
	rooms     map[string]map[Conn]*member
	last      map[string][]byte
	spans     map[string][]byte
	spotlight []byte
	docDirs   map[string]string
}

// member is one connection in a room. Its mutex serializes everything that is
// written to the connection, so a seed that JoinAndSeed is still delivering is
// never overtaken by a broadcast that arrived after the join.
type member struct {
	mu sync.Mutex
}

// target is a snapshot entry taken for a fan-out: the connection and the lock
// that orders writes to it.
type target struct {
	c Conn
	m *member
}

func NewRegistry() *Registry {
	return &Registry{
		rooms:   make(map[string]map[Conn]*member),
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

// Join adds c to the room for key, without seeding it. A transport that wants
// the current state delivered uses JoinAndSeed instead: calling Join and then
// LastPayload/LastSpans/LastSpotlight leaves a window in which a broadcast
// reaches c first and the older state read before it is delivered after.
func (r *Registry) Join(key string, c Conn) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.joinLocked(key, c)
}

// joinLocked registers c in key's room and returns its member record. Caller
// must hold r.mu.
func (r *Registry) joinLocked(key string, c Conn) *member {
	if r.rooms[key] == nil {
		r.rooms[key] = make(map[Conn]*member)
	}
	m := &member{}
	r.rooms[key][c] = m
	return m
}

// JoinAndSeed adds c to the room for key and sends it the current state: the
// content, then the fence highlights (the client paints them onto a rendered
// document, so they must come second), then the spotlight mirror state.
//
// Registration and the reading of that state happen under one lock, and
// c's own write lock is taken before that lock is released, so a broadcast
// that follows the join is delivered after the seed instead of before it: c
// can never end on an older state than the one a broadcast already carried.
// A broadcast that preceded the join is simply part of the seed.
//
// Returns the first send error; c stays joined, and the caller leaves the room
// as it does after any failed connection.
func (r *Registry) JoinAndSeed(key string, c Conn) error {
	r.mu.Lock()
	m := r.joinLocked(key, c)
	m.mu.Lock()
	seeds := make([][]byte, 0, 3)
	if p, ok := r.last[key]; ok {
		seeds = append(seeds, p)
	}
	if p, ok := r.spans[key]; ok {
		seeds = append(seeds, p)
	}
	if r.spotlight != nil {
		seeds = append(seeds, r.spotlight)
	}
	r.mu.Unlock()
	defer m.mu.Unlock()

	for _, p := range seeds {
		if err := c.Send(p); err != nil {
			return err
		}
	}
	return nil
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

// LastSpotlight returns the most recently broadcast spotlight-mirror state, if
// any. It is global rather than per room: the spotlights are Neovim's, and mark
// the same tokens in whatever document a tab happens to show.
func (r *Registry) LastSpotlight() ([]byte, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.spotlight, r.spotlight != nil
}

// BroadcastSpotlight stores payload as the latest spotlight-mirror state and
// sends it to every connection in every room.
//
// Stored (a joining or reloading tab is seeded with it, so the highlights are
// there at once instead of after the next change in Neovim) and global (see
// LastSpotlight) -- the one state in the relay that belongs to no document.
// The relay never inspects the payload, it only forwards and remembers it.
func (r *Registry) BroadcastSpotlight(payload []byte) []error {
	r.mu.Lock()
	r.spotlight = payload
	var conns []target
	for key := range r.rooms {
		conns = append(conns, r.connsForLocked(key)...)
	}
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
	var conns []target
	for key := range r.rooms {
		conns = append(conns, r.connsForLocked(key)...)
	}
	r.mu.Unlock()

	return sendAll(conns, payload)
}

// connsForLocked snapshots the current members of key's room. Caller must
// hold r.mu.
func (r *Registry) connsForLocked(key string) []target {
	conns := make([]target, 0, len(r.rooms[key]))
	for c, m := range r.rooms[key] {
		conns = append(conns, target{c: c, m: m})
	}
	return conns
}

// sendAll delivers payload to every target. Each write is taken under the
// target's lock, which waits out a seed still on its way (see JoinAndSeed).
func sendAll(conns []target, payload []byte) []error {
	var errs []error
	for _, t := range conns {
		t.m.mu.Lock()
		err := t.c.Send(payload)
		t.m.mu.Unlock()
		if err != nil {
			errs = append(errs, err)
		}
	}
	return errs
}

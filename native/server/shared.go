package main

// Shared relay (`--shared`): one relay process, one preview tab, for every
// Neovim instance of the user. The first instance spawns the relay detached
// from itself and the relay advertises itself in a discovery file; later
// instances read that file and attach instead of spawning a relay of their own.
//
// The relay stays a byte forwarder. What it adds in shared mode is
// bookkeeping: which instances are attached (every request naming a `client`
// is a heartbeat), which instance owns each room (the last one that pushed
// content or a document into it -- the focused one, since only it pushes), and
// a lifetime of its own: it ends once no instance has been heard from for a
// while, instead of dying with the instance that started it.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/StefanBartl/mdview.nvim/native/server/internal/relay"
)

type ownerFilterKey struct{}

// ownerFilter returns the room filter withClients attached to r: the rooms
// the polling instance owns. nil (drain everything) for an anonymous poller or
// an unshared relay.
func ownerFilter(r *http.Request) func(key string) bool {
	f, _ := r.Context().Value(ownerFilterKey{}).(func(key string) bool)
	return f
}

// withClients wraps the relay's routes for shared mode. For an authenticated
// request that names a `client` it records the heartbeat, makes that client
// the owner of the room when it pushes content (/update) or names the
// document on screen (/doc), and hands the drain handlers the client's room
// filter. A nil clients (unshared relay) passes every request through as is.
func withClients(clients *relay.Clients, token string, next http.Handler) http.Handler {
	if clients == nil {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		client := q.Get("client")
		if client == "" || len(client) > maxClientIDLen || !relay.ValidToken(token, q.Get("token")) {
			next.ServeHTTP(w, r)
			return
		}
		clients.Touch(client, time.Now())
		if r.Method == http.MethodPost && (r.URL.Path == "/update" || r.URL.Path == "/doc") {
			clients.SetOwner(q.Get("key"), client)
		}
		mine := func(key string) bool { return clients.Mine(client, key) }
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ownerFilterKey{}, mine)))
	})
}

// maxClientIDLen bounds the instance id a request names (it is kept in memory).
const maxClientIDLen = 128

// handleAttach answers GET /attach with the relay's shared status (protocol,
// attached instances, room owners, rooms with a tab). The heartbeat itself is
// recorded by withClients; on an unshared relay this still answers, with
// shared=false, so an instance can tell the two apart.
func handleAttach(clients *relay.Clients, registry *relay.Registry, token string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if !relay.ValidToken(token, r.URL.Query().Get("token")) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		_ = json.NewEncoder(w).Encode(clients.Status(registry.TabRooms()))
	}
}

// handleDetach (POST /detach?client=...) removes an instance that is leaving
// (:MDView stop, quitting Neovim). Answers the number of instances left.
func handleDetach(clients *relay.Clients, token string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		q := r.URL.Query()
		if !relay.ValidToken(token, q.Get("token")) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		left := clients.Detach(q.Get("client"))
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]int{"clients": left})
	}
}

// discovery is the content of the discovery file: where the shared relay
// listens and the token it accepts.
type discovery struct {
	Protocol int    `json:"protocol"`
	Port     int    `json:"port"`
	Token    string `json:"token"`
	PID      int    `json:"pid"`
}

// writeDiscovery writes the discovery file, readable by the user only (it
// holds the session token). Written to a temp file first and renamed, so an
// instance never reads half a file.
func writeDiscovery(path string, d discovery) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.Marshal(d)
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// removeDiscovery deletes the discovery file, but only while it still names
// this relay: a newer relay may have replaced it after this one was given up
// on, and its file must survive this one's exit.
func removeDiscovery(path, token string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	var d discovery
	if json.Unmarshal(data, &d) != nil || d.Token != token {
		return
	}
	_ = os.Remove(path)
}

// lifetime decides when a shared relay ends. Before any instance attached it
// waits `timeout` (the instance that spawned it attaches as soon as it is up);
// afterwards it ends `grace` after the last instance left or went silent.
type lifetime struct {
	clients *relay.Clients
	timeout time.Duration
	grace   time.Duration
	tick    time.Duration

	started    time.Time
	lastTick   time.Time
	emptySince time.Time
}

func newLifetime(clients *relay.Clients, timeout time.Duration, now time.Time) *lifetime {
	return &lifetime{
		clients:  clients,
		timeout:  timeout,
		grace:    2 * time.Second,
		tick:     time.Second,
		started:  now,
		lastTick: now,
	}
}

// step runs one check at now and reports whether the relay should end.
//
// A tick that comes much later than scheduled means the machine slept (or the
// process was stopped): nobody could send a heartbeat meanwhile, so the
// instances are refreshed instead of pruned for a silence that was not theirs.
func (l *lifetime) step(now time.Time) bool {
	if now.Sub(l.lastTick) > 5*l.tick {
		l.clients.Refresh(now)
		if !l.emptySince.IsZero() {
			l.emptySince = now
		}
	}
	l.lastTick = now

	if !l.clients.EverAttached() {
		return now.Sub(l.started) > l.timeout
	}
	if l.clients.Prune(now, l.timeout) > 0 {
		l.emptySince = time.Time{}
		return false
	}
	if l.emptySince.IsZero() {
		l.emptySince = now
	}
	return now.Sub(l.emptySince) >= l.grace
}

// runSharedLifetime blocks until the relay should end, then closes every tab
// (nobody is left to feed them) and removes the discovery file.
func runSharedLifetime(l *lifetime, registry *relay.Registry, discoveryPath, token string) {
	t := time.NewTicker(l.tick)
	defer t.Stop()
	for now := range t.C {
		if l.step(now) {
			break
		}
	}
	fmt.Println("[shared] no Neovim instance attached any more, exiting")
	registry.BroadcastAllEphemeral([]byte(closeMessagePrefix))
	if discoveryPath != "" {
		removeDiscovery(discoveryPath, token)
	}
}

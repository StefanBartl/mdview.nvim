package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/StefanBartl/mdview.nvim/native/server/internal/relay"
)

// sharedMux builds the routes a shared relay serves, behind withClients.
func sharedMux(clients *relay.Clients, queue *relay.ToggleQueue) http.Handler {
	registry := relay.NewRegistry()
	mux := http.NewServeMux()
	mux.HandleFunc("/update", handleUpdate(registry, testToken))
	mux.HandleFunc("/doc", handleDoc(registry, testToken))
	mux.HandleFunc("/toggle", handleToggle(queue, "", "", testToken))
	mux.HandleFunc("/attach", handleAttach(clients, registry, testToken))
	mux.HandleFunc("/detach", handleDetach(clients, testToken))
	return withClients(clients, testToken, mux)
}

func do(t *testing.T, h http.Handler, method, path string, q url.Values, body string) *httptest.ResponseRecorder {
	t.Helper()
	q.Set("token", testToken)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path+"?"+q.Encode(), strings.NewReader(body)))
	return rec
}

func drainToggles(t *testing.T, h http.Handler, client string) []relay.ToggleRequest {
	t.Helper()
	q := url.Values{}
	if client != "" {
		q.Set("client", client)
	}
	rec := do(t, h, http.MethodGet, "/toggle", q, "")
	var got []relay.ToggleRequest
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	return got
}

// Acceptance: a write-back lands in the instance that owns the document on
// screen, not in whichever instance polls first.
func TestShared_WriteBackGoesToTheRoomOwner(t *testing.T) {
	clients := relay.NewClients()
	queue := relay.NewToggleQueue()
	h := sharedMux(clients, queue)

	// Instance a pushes the room first, then b (the focused one) takes it over.
	do(t, h, http.MethodPost, "/update", url.Values{"key": {"room.md"}, "client": {"a"}}, "# a")
	do(t, h, http.MethodPost, "/doc", url.Values{"key": {"room.md"}, "client": {"b"}}, "/notes/b.md")

	if rec := do(t, h, http.MethodPost, "/toggle", url.Values{"key": {"room.md"}, "doc": {"/notes/b.md"}}, "2:1"); rec.Code != http.StatusNoContent {
		t.Fatalf("toggle status = %d", rec.Code)
	}
	if got := drainToggles(t, h, "a"); len(got) != 0 {
		t.Fatalf("instance a drained b's toggle: %+v", got)
	}
	got := drainToggles(t, h, "b")
	if len(got) != 1 || got[0].Line != 2 {
		t.Fatalf("instance b got %+v, want its toggle", got)
	}
}

func TestShared_AnonymousPollerStillDrainsEverything(t *testing.T) {
	h := sharedMux(relay.NewClients(), relay.NewToggleQueue())
	do(t, h, http.MethodPost, "/doc", url.Values{"key": {"room.md"}, "client": {"b"}}, "/notes/b.md")
	do(t, h, http.MethodPost, "/toggle", url.Values{"key": {"room.md"}}, "2:1")
	if got := drainToggles(t, h, ""); len(got) != 1 {
		t.Fatalf("an instance that does not name itself must drain everything, got %+v", got)
	}
}

func TestShared_AWrongTokenNeitherTouchesNorOwns(t *testing.T) {
	clients := relay.NewClients()
	h := sharedMux(clients, relay.NewToggleQueue())
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/doc?token=nope&key=room.md&client=evil", strings.NewReader("/x.md")))
	if _, ok := clients.Owner("room.md"); ok || clients.EverAttached() {
		t.Fatal("an unauthenticated request must not attach or take a room")
	}
}

func TestShared_AttachReportsStatusAndDetachCounts(t *testing.T) {
	clients := relay.NewClients()
	h := sharedMux(clients, relay.NewToggleQueue())
	do(t, h, http.MethodGet, "/attach", url.Values{"client": {"a"}}, "")
	rec := do(t, h, http.MethodGet, "/attach", url.Values{"client": {"b"}}, "")
	var st relay.Status
	if err := json.Unmarshal(rec.Body.Bytes(), &st); err != nil {
		t.Fatal(err)
	}
	if !st.Shared || st.Protocol != relay.SharedProtocol || st.Clients != 2 || st.Tabs == nil {
		t.Fatalf("status = %+v", st)
	}
	rec = do(t, h, http.MethodPost, "/detach", url.Values{"client": {"a"}}, "")
	if !strings.Contains(rec.Body.String(), `"clients":1`) {
		t.Fatalf("detach answered %q", rec.Body.String())
	}
}

func TestShared_UnsharedRelayAnswersAttachWithSharedFalse(t *testing.T) {
	registry := relay.NewRegistry()
	rec := httptest.NewRecorder()
	handleAttach(nil, registry, testToken)(rec, httptest.NewRequest(http.MethodGet, "/attach?token="+testToken, nil))
	var st relay.Status
	if err := json.Unmarshal(rec.Body.Bytes(), &st); err != nil || st.Shared {
		t.Fatalf("unshared relay status = %q (%v)", rec.Body.String(), err)
	}
}

// Acceptance: the relay outlives the instance that spawned it and ends only
// when no instance is attached any more.
func TestShared_LifetimeEndsOnlyWhenNobodyIsLeft(t *testing.T) {
	clients := relay.NewClients()
	t0 := time.Now()
	l := newLifetime(clients, 30*time.Second, t0)

	if l.step(t0.Add(time.Second)) {
		t.Fatal("must wait for the first instance to attach")
	}
	clients.Touch("a", t0.Add(time.Second))
	clients.Touch("b", t0.Add(time.Second))
	clients.Detach("a") // the instance that spawned the relay quits
	if l.step(t0.Add(2 * time.Second)) {
		t.Fatal("must keep running while b is attached")
	}
	clients.Detach("b")
	if l.step(t0.Add(3 * time.Second)) {
		t.Fatal("must allow a short grace after the last instance left")
	}
	if !l.step(t0.Add(5 * time.Second)) {
		t.Fatal("must end once nobody is attached")
	}
}

func TestShared_LifetimeGivesUpWithoutAnyInstance(t *testing.T) {
	t0 := time.Now()
	l := newLifetime(relay.NewClients(), 30*time.Second, t0)
	for s := 1; s <= 30; s++ {
		if l.step(t0.Add(time.Duration(s) * time.Second)) {
			t.Fatalf("gave up after %ds, want 30s", s)
		}
	}
	if !l.step(t0.Add(31 * time.Second)) {
		t.Fatal("must end when no instance ever attached")
	}
}

func TestShared_LifetimeSurvivesASleep(t *testing.T) {
	clients := relay.NewClients()
	t0 := time.Now()
	l := newLifetime(clients, 30*time.Second, t0)
	clients.Touch("a", t0)
	l.step(t0.Add(time.Second))
	// The machine sleeps for an hour: no tick, no heartbeat.
	if l.step(t0.Add(time.Hour)) {
		t.Fatal("a sleep is not the instances' silence")
	}
}

func TestShared_DiscoveryFileIsRemovedOnlyByItsRelay(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mdview", "relay.json")
	if err := writeDiscovery(path, discovery{Protocol: 1, Port: 43219, Token: "mine", PID: 1}); err != nil {
		t.Fatal(err)
	}
	removeDiscovery(path, "someone-else")
	if _, err := os.Stat(path); err != nil {
		t.Fatal("a relay must not remove a file that names another relay")
	}
	removeDiscovery(path, "mine")
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("the relay must remove its own discovery file")
	}
}

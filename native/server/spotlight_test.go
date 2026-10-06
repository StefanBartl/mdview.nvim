package main

// handleSpotlight tests: a thin auth + size-cap + broadcast wrapper around
// Registry (whose own behavior is covered in internal/relay), so what is pinned
// here is the part that is this handler's: who may post, how much, and that the
// payload leaves tagged and stored.

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/StefanBartl/mdview.nvim/native/server/internal/relay"
)

type recordingConn struct{ received []string }

func (c *recordingConn) Send(payload []byte) error {
	c.received = append(c.received, string(payload))
	return nil
}

func spotlightRequest(method, token, body string) *http.Request {
	target := "/spotlight"
	if token != "" {
		target += "?token=" + token
	}
	return httptest.NewRequest(method, target, strings.NewReader(body))
}

func TestHandleSpotlight_BroadcastsTaggedPayloadToEveryRoomAndStoresIt(t *testing.T) {
	registry := relay.NewRegistry()
	a, b := &recordingConn{}, &recordingConn{}
	registry.Join("/doc/a.md", a)
	registry.Join("/doc/b.md", b)

	w := httptest.NewRecorder()
	handleSpotlight(registry, testToken).ServeHTTP(w, spotlightRequest(http.MethodPost, testToken, `{"items":[]}`))

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", w.Code, w.Body.String())
	}
	want := spotlightMessagePrefix + `{"items":[]}`
	for name, c := range map[string]*recordingConn{"a": a, "b": b} {
		if len(c.received) != 1 || c.received[0] != want {
			t.Fatalf("room %s: expected %q, got %q", name, want, c.received)
		}
	}
	stored, ok := registry.LastSpotlight()
	if !ok || string(stored) != want {
		t.Fatalf("expected the state to be stored for late joiners, got %q (ok=%v)", stored, ok)
	}
}

func TestHandleSpotlight_RejectsWrongAndMissingToken(t *testing.T) {
	registry := relay.NewRegistry()
	for _, token := range []string{"wrong", ""} {
		w := httptest.NewRecorder()
		handleSpotlight(registry, testToken).ServeHTTP(w, spotlightRequest(http.MethodPost, token, "{}"))
		if w.Code != http.StatusForbidden {
			t.Fatalf("token %q: expected 403, got %d", token, w.Code)
		}
	}
	if _, ok := registry.LastSpotlight(); ok {
		t.Fatalf("a rejected request must not store anything")
	}
}

func TestHandleSpotlight_RejectsNonPost(t *testing.T) {
	w := httptest.NewRecorder()
	handleSpotlight(relay.NewRegistry(), testToken).ServeHTTP(w, spotlightRequest(http.MethodGet, testToken, ""))
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestHandleSpotlight_RejectsAnOversizedBody(t *testing.T) {
	registry := relay.NewRegistry()
	body := strings.Repeat("x", maxSpotlightBodyBytes+1)

	w := httptest.NewRecorder()
	handleSpotlight(registry, testToken).ServeHTTP(w, spotlightRequest(http.MethodPost, testToken, body))

	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413, got %d", w.Code)
	}
	if _, ok := registry.LastSpotlight(); ok {
		t.Fatalf("an oversized payload must not be stored")
	}
}

func TestHandleSpotlight_AcceptsABodyExactlyAtTheCap(t *testing.T) {
	w := httptest.NewRecorder()
	body := strings.Repeat("x", maxSpotlightBodyBytes)
	handleSpotlight(relay.NewRegistry(), testToken).ServeHTTP(w, spotlightRequest(http.MethodPost, testToken, body))
	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204 at the cap, got %d", w.Code)
	}
}

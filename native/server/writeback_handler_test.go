package main

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"

	"github.com/StefanBartl/mdview.nvim/native/server/internal/relay"
)

// The checkbox and text-field bridges carry `doc`, the document the tab is
// showing: under browser.behavior=reuse the tab's key is a room, not that
// document, and Neovim must edit the buffer of the document on screen.

func togglePost(t *testing.T, h http.HandlerFunc, key, doc, body string) *httptest.ResponseRecorder {
	t.Helper()
	target := "/toggle?token=" + url.QueryEscape(testToken) + "&key=" + url.QueryEscape(key)
	if doc != "" {
		target += "&doc=" + url.QueryEscape(doc)
	}
	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodPost, target, strings.NewReader(body)))
	return rec
}

func fieldPost(t *testing.T, h http.HandlerFunc, key, doc, body string) *httptest.ResponseRecorder {
	t.Helper()
	target := "/field?token=" + url.QueryEscape(testToken) + "&key=" + url.QueryEscape(key)
	if doc != "" {
		target += "&doc=" + url.QueryEscape(doc)
	}
	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodPost, target, strings.NewReader(body)))
	return rec
}

func TestHandleToggle_NeovimModeCarriesTheDocument(t *testing.T) {
	queue := relay.NewToggleQueue()
	h := handleToggle(queue, "", "", testToken)

	if rec := togglePost(t, h, "room.md", "/notes/other.md", "3:1"); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	got := queue.Drain()
	if len(got) != 1 || got[0].Key != "room.md" || got[0].Doc != "/notes/other.md" || got[0].Line != 3 || !got[0].Checked {
		t.Fatalf("queued = %+v", got)
	}
}

func TestHandleToggle_DocIsOptionalAndBounded(t *testing.T) {
	queue := relay.NewToggleQueue()
	h := handleToggle(queue, "", "", testToken)

	if rec := togglePost(t, h, "room.md", "", "3:0"); rec.Code != http.StatusNoContent {
		t.Fatalf("without doc: status = %d, want 204", rec.Code)
	}
	if got := queue.Drain(); len(got) != 1 || got[0].Doc != "" {
		t.Fatalf("queued = %+v", got)
	}
	if rec := togglePost(t, h, "room.md", strings.Repeat("d", maxDocLen+1), "3:0"); rec.Code != http.StatusBadRequest {
		t.Fatalf("long doc: status = %d, want 400", rec.Code)
	}
	if got := queue.Drain(); got != nil {
		t.Fatalf("a refused toggle was queued: %+v", got)
	}
}

func TestHandleToggle_StandaloneStillAppliesToTheFile(t *testing.T) {
	p := mustWriteFile(t, t.TempDir(), "doc.md", "- [ ] one\n")
	key := filepath.ToSlash(p)
	h := handleToggle(relay.NewToggleQueue(), key, p, testToken)

	if rec := togglePost(t, h, key, key, "1:1"); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if got, want := readFile(t, p), "- [x] one\n"; got != want {
		t.Fatalf("file = %q, want %q", got, want)
	}
}

func TestHandleField_NeovimModeCarriesTheDocument(t *testing.T) {
	queue := relay.NewFieldQueue()
	h := handleField(queue, "", "", testToken)

	body := `{"name":"title","value":"Hello"}`
	if rec := fieldPost(t, h, "room.md", "/notes/other.md", body); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	got := queue.Drain()
	if len(got) != 1 || got[0].Key != "room.md" || got[0].Doc != "/notes/other.md" || got[0].Name != "title" || got[0].Value != "Hello" {
		t.Fatalf("queued = %+v", got)
	}
}

func TestHandleField_RejectsATooLongDoc(t *testing.T) {
	queue := relay.NewFieldQueue()
	h := handleField(queue, "", "", testToken)

	body := `{"name":"title","value":"x"}`
	if rec := fieldPost(t, h, "room.md", strings.Repeat("d", maxDocLen+1), body); rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
	if got := queue.Drain(); got != nil {
		t.Fatalf("a refused edit was queued: %+v", got)
	}
}

func TestHandleToggle_StandaloneStaleLineIs409AndKeyMismatchIs404(t *testing.T) {
	p := mustWriteFile(t, t.TempDir(), "doc.md", "- [ ] one\n- [ ] two\n")
	key := filepath.ToSlash(p)
	queue := relay.NewToggleQueue()
	h := handleToggle(queue, key, p, testToken)

	// the tab meant "- [ ] two" at line 1, but the line is another one now
	target := "/toggle?token=" + testToken + "&key=" + url.QueryEscape(key) + "&expected=" + url.QueryEscape("- [ ] two")
	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodPost, target, strings.NewReader("1:1")))
	if rec.Code != http.StatusConflict {
		t.Fatalf("stale: status = %d, want 409", rec.Code)
	}
	if got, want := readFile(t, p), "- [ ] one\n- [ ] two\n"; got != want {
		t.Fatalf("file changed: %q", got)
	}

	// a room that is not the watched file: nobody would drain a queue
	if rec := togglePost(t, h, "some/other.md", "", "1:1"); rec.Code != http.StatusNotFound {
		t.Fatalf("key mismatch: status = %d, want 404", rec.Code)
	}
	if got := queue.Drain(); got != nil {
		t.Fatalf("a request for another room was queued in standalone mode: %+v", got)
	}
}

func TestHandleToggle_NeovimModeQueuesTheExpectedLine(t *testing.T) {
	queue := relay.NewToggleQueue()
	h := handleToggle(queue, "", "", testToken)

	target := "/toggle?token=" + testToken + "&key=room.md&expected=" + url.QueryEscape("- [ ] one")
	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodPost, target, strings.NewReader("3:1")))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	got := queue.Drain()
	if len(got) != 1 || got[0].Expected != "- [ ] one" {
		t.Fatalf("queued = %+v", got)
	}

	long := "/toggle?token=" + testToken + "&key=room.md&expected=" + strings.Repeat("x", maxExpectedLen+1)
	// over the bound the tick is not lost: it is queued without the guard
	rec = httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodPost, long, strings.NewReader("3:1")))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("long expected: status = %d, want 204", rec.Code)
	}
	got = queue.Drain()
	if len(got) != 1 || got[0].Expected != "" || got[0].Line != 3 {
		t.Fatalf("long expected queued = %+v, want line 3 without an expected line", got)
	}
}

func TestHandleToggle_StandaloneLongExpectedStillTicks(t *testing.T) {
	p := mustWriteFile(t, t.TempDir(), "doc.md", "- [ ] "+strings.Repeat("w", maxExpectedLen)+"\n")
	key := filepath.ToSlash(p)
	h := handleToggle(relay.NewToggleQueue(), key, p, testToken)

	target := "/toggle?token=" + testToken + "&key=" + url.QueryEscape(key) + "&expected=" + url.QueryEscape("- [ ] "+strings.Repeat("w", maxExpectedLen))
	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodPost, target, strings.NewReader("1:1")))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if got := readFile(t, p); !strings.HasPrefix(got, "- [x] ") {
		t.Fatalf("not ticked: %q", got[:10])
	}
}

func TestWriteBackRoutes_RejectAMalformedQueryAndATooLongKey(t *testing.T) {
	routes := map[string]http.HandlerFunc{
		"/toggle": handleToggle(relay.NewToggleQueue(), "", "", testToken),
		"/field":  handleField(relay.NewFieldQueue(), "", "", testToken),
		"/edit":   handleEdit(relay.NewEditQueue(), "", "", testToken, false),
	}
	bodies := map[string]string{
		"/toggle": "1:1",
		"/field":  `{"name":"n","value":"v"}`,
		"/edit":   `{"start":1,"end":1,"expected":"a","text":"b"}`,
	}
	for route, h := range routes {
		// "%zz" is not a percent escape: the pair is not silently dropped
		rec := httptest.NewRecorder()
		h(rec, httptest.NewRequest(http.MethodPost, route+"?token="+testToken+"&key=room.md&doc=%zz", strings.NewReader(bodies[route])))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s malformed query: status = %d, want 400", route, rec.Code)
		}
		rec = httptest.NewRecorder()
		h(rec, httptest.NewRequest(http.MethodPost, route+"?token="+testToken+"&key="+strings.Repeat("k", maxDocLen+1), strings.NewReader(bodies[route])))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s long key: status = %d, want 400", route, rec.Code)
		}
	}
}

// A document ping the relay has seen is replayed to a tab that joins later (a
// reload), right after the content: the ping is sent once per buffer switch and
// the tab renders by the name it carries.
func TestHandleDoc_ReplaysThePingToALateJoiner(t *testing.T) {
	registry := relay.NewRegistry()
	registry.Broadcast("room.md", []byte("content"))
	h := handleDoc(registry, testToken)

	target := "/doc?token=" + url.QueryEscape(testToken) + "&key=room.md"
	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodPost, target, strings.NewReader("/x/other.py")))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}

	late := &recordingConn{}
	if err := registry.JoinAndSeed("room.md", late); err != nil {
		t.Fatalf("JoinAndSeed: %v", err)
	}
	want := []string{"content", docMessagePrefix + "/x/other.py"}
	if len(late.received) != len(want) {
		t.Fatalf("seeds = %q, want %q", late.received, want)
	}
	for i, w := range want {
		if late.received[i] != w {
			t.Fatalf("seed %d = %q, want %q", i, late.received[i], w)
		}
	}
}

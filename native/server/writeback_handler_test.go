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

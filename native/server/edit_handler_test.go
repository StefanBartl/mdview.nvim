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

	"github.com/StefanBartl/mdview.nvim/native/server/internal/relay"
)

func editPost(t *testing.T, h http.HandlerFunc, key, token, body string) *httptest.ResponseRecorder {
	t.Helper()
	return editPostDoc(t, h, key, "", token, body)
}

func editPostDoc(t *testing.T, h http.HandlerFunc, key, doc, token, body string) *httptest.ResponseRecorder {
	t.Helper()
	target := "/edit?token=" + url.QueryEscape(token) + "&key=" + url.QueryEscape(key)
	if doc != "" {
		target += "&doc=" + url.QueryEscape(doc)
	}
	req := httptest.NewRequest(http.MethodPost, target, strings.NewReader(body))
	rec := httptest.NewRecorder()
	h(rec, req)
	return rec
}

func readFile(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

const editBody = `{"start":2,"end":2,"expected":"old","text":"new"}`

func TestHandleEdit_StandaloneAppliesTheEdit(t *testing.T) {
	p := mustWriteFile(t, t.TempDir(), "doc.md", "a\nold\nb\n")
	key := filepath.ToSlash(p)
	h := handleEdit(relay.NewEditQueue(), key, p, testToken, true)

	rec := editPost(t, h, key, testToken, editBody)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if got, want := readFile(t, p), "a\nnew\nb\n"; got != want {
		t.Fatalf("file = %q, want %q", got, want)
	}
}

func TestHandleEdit_StaleEditIs409AndLeavesTheFile(t *testing.T) {
	p := mustWriteFile(t, t.TempDir(), "doc.md", "a\nsomething else\nb\n")
	key := filepath.ToSlash(p)
	h := handleEdit(relay.NewEditQueue(), key, p, testToken, true)

	if rec := editPost(t, h, key, testToken, editBody); rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", rec.Code)
	}
	if got, want := readFile(t, p), "a\nsomething else\nb\n"; got != want {
		t.Fatalf("file changed: %q", got)
	}
}

func TestHandleEdit_StandaloneWithoutEditFlagIsForbidden(t *testing.T) {
	p := mustWriteFile(t, t.TempDir(), "doc.md", "a\nold\nb\n")
	key := filepath.ToSlash(p)
	h := handleEdit(relay.NewEditQueue(), key, p, testToken, false)

	if rec := editPost(t, h, key, testToken, editBody); rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", rec.Code)
	}
	if got, want := readFile(t, p), "a\nold\nb\n"; got != want {
		t.Fatalf("file changed: %q", got)
	}
}

func TestHandleEdit_RejectsWrongTokenAndBadPayloads(t *testing.T) {
	p := mustWriteFile(t, t.TempDir(), "doc.md", "a\nold\nb\n")
	key := filepath.ToSlash(p)
	h := handleEdit(relay.NewEditQueue(), key, p, testToken, true)

	cases := []struct {
		name  string
		token string
		body  string
		want  int
	}{
		{"wrong token", "nope", editBody, http.StatusForbidden},
		{"not json", testToken, "start=2", http.StatusBadRequest},
		{"start below 1", testToken, `{"start":0,"end":1,"expected":"","text":""}`, http.StatusBadRequest},
		{"end before start", testToken, `{"start":3,"end":2,"expected":"","text":""}`, http.StatusBadRequest},
		{"too large", testToken, `{"start":1,"end":1,"expected":"","text":"` + strings.Repeat("x", maxEditBodyBytes) + `"}`, http.StatusRequestEntityTooLarge},
	}
	for _, c := range cases {
		if rec := editPost(t, h, key, c.token, c.body); rec.Code != c.want {
			t.Errorf("%s: status = %d, want %d", c.name, rec.Code, c.want)
		}
	}
	if got, want := readFile(t, p), "a\nold\nb\n"; got != want {
		t.Fatalf("file changed: %q", got)
	}
}

func TestHandleEdit_NeovimModeQueuesAndGetDrains(t *testing.T) {
	queue := relay.NewEditQueue()
	h := handleEdit(queue, "", "", testToken, false) // no standalone watch: queued for Neovim

	if rec := editPost(t, h, "doc.md", testToken, editBody); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}

	get := httptest.NewRecorder()
	h(get, httptest.NewRequest(http.MethodGet, "/edit?token="+testToken, nil))
	var got []relay.EditRequest
	if err := json.Unmarshal(get.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Key != "doc.md" || got[0].Start != 2 || got[0].Expected != "old" || got[0].Text != "new" {
		t.Fatalf("drained = %+v", got)
	}

	again := httptest.NewRecorder()
	h(again, httptest.NewRequest(http.MethodGet, "/edit?token="+testToken, nil))
	if strings.TrimSpace(again.Body.String()) != "null" {
		t.Fatalf("second drain = %q, want null", again.Body.String())
	}
}

func TestHandleEdit_NeovimModeCarriesTheDocument(t *testing.T) {
	queue := relay.NewEditQueue()
	h := handleEdit(queue, "", "", testToken, false)

	// the tab's room is "room.md" but it is showing "other.md" (reuse behavior)
	if rec := editPostDoc(t, h, "room.md", "/notes/other.md", testToken, editBody); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	got := queue.Drain()
	if len(got) != 1 || got[0].Key != "room.md" || got[0].Doc != "/notes/other.md" {
		t.Fatalf("queued = %+v", got)
	}
}

func TestHandleEdit_RejectsOtherMethods(t *testing.T) {
	h := handleEdit(relay.NewEditQueue(), "", "", testToken, false)
	req := httptest.NewRequest(http.MethodPut, "/edit?token="+testToken, nil)
	rec := httptest.NewRecorder()
	h(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", rec.Code)
	}
}

func TestHandleEdit_StandaloneKeyMismatchIs404AndTooLongDocIs400(t *testing.T) {
	p := mustWriteFile(t, t.TempDir(), "doc.md", "a\nold\nb\n")
	key := filepath.ToSlash(p)
	h := handleEdit(relay.NewEditQueue(), key, p, testToken, true)

	if rec := editPost(t, h, "some/other.md", testToken, editBody); rec.Code != http.StatusNotFound {
		t.Fatalf("key mismatch: status = %d, want 404", rec.Code)
	}
	if rec := editPostDoc(t, h, key, strings.Repeat("d", maxDocLen+1), testToken, editBody); rec.Code != http.StatusBadRequest {
		t.Fatalf("long doc: status = %d, want 400", rec.Code)
	}
	if got, want := readFile(t, p), "a\nold\nb\n"; got != want {
		t.Fatalf("file changed: %q", got)
	}
}

func TestHandleEdit_ReadOnlyFileIs403(t *testing.T) {
	p := mustWriteFile(t, t.TempDir(), "doc.md", "a\nold\nb\n")
	if err := os.Chmod(p, 0o444); err != nil {
		t.Skipf("cannot make the file read-only here: %v", err)
	}
	defer func() { _ = os.Chmod(p, 0o644) }()
	key := filepath.ToSlash(p)
	h := handleEdit(relay.NewEditQueue(), key, p, testToken, true)

	if rec := editPost(t, h, key, testToken, editBody); rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", rec.Code)
	}
}

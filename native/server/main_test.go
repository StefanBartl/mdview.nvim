package main

// handleAsset tests: this endpoint's whole job is serving a file from
// outside the web-root file server, so the containment/allowlist checks are
// the security boundary of the feature — worth their own coverage, unlike
// the other handlers in this file (thin auth+broadcast wrappers around
// Registry, already covered by internal/relay's own tests).

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/StefanBartl/mdview.nvim/native/server/internal/relay"
)

const testToken = "test-token"

func mustWriteFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}
	return p
}

func assetRequest(key, path, token string) *http.Request {
	q := "/asset?key=" + key + "&path=" + path
	if token != "" {
		q += "&token=" + token
	}
	return httptest.NewRequest(http.MethodGet, q, nil)
}

func TestHandleAsset_ServesImageInsideDocDir(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, "photo.png", "fake-png-bytes")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handleAsset(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, assetRequest("session-1", "photo.png", testToken))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if w.Body.String() != "fake-png-bytes" {
		t.Fatalf("expected file contents in response body, got %q", w.Body.String())
	}
}

func TestHandleAsset_ServesImageInSubdirectory(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, filepath.Join("assets", "photo.png"), "nested-png")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handleAsset(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, assetRequest("session-1", "assets/photo.png", testToken))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHandleAsset_RejectsPathTraversalOutsideDocDir(t *testing.T) {
	dir := t.TempDir()
	parent := filepath.Dir(dir)
	mustWriteFile(t, parent, "secret.png", "should never be served")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handleAsset(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, assetRequest("session-1", "../secret.png", testToken))

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for a path escaping the doc dir, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHandleAsset_RejectsDisallowedExtension(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, "notes.txt", "arbitrary file content")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handleAsset(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, assetRequest("session-1", "notes.txt", testToken))

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for a non-image extension, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHandleAsset_RejectsWrongToken(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, "photo.png", "png-bytes")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handleAsset(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, assetRequest("session-1", "photo.png", "wrong-token"))

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for an invalid token, got %d", w.Code)
	}
}

func TestHandleAsset_RejectsUnknownSession(t *testing.T) {
	registry := relay.NewRegistry() // no SetDocDir call for "session-1"

	h := handleAsset(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, assetRequest("session-1", "photo.png", testToken))

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for a session with no recorded doc dir, got %d", w.Code)
	}
}

func TestHandleAsset_RejectsNonGet(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, "photo.png", "png-bytes")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handleAsset(registry, testToken)
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/asset?key=session-1&path=photo.png&token="+testToken, nil)
	h.ServeHTTP(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405 for a POST request, got %d", w.Code)
	}
}

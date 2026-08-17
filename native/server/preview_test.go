package main

// handlePreview tests. Like handleAsset, this endpoint reaches outside the
// web-root file server, so its containment/allowlist checks are the security
// boundary of the browser hover feature. It goes one step further than
// /asset — it returns file *contents* as text rather than bytes a browser
// renders as a picture — so the byte/line caps are covered here too.

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/StefanBartl/mdview.nvim/native/server/internal/relay"
)

func mustMkdir(t *testing.T, parent, name string) string {
	t.Helper()
	p := filepath.Join(parent, name)
	if err := os.MkdirAll(p, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	return p
}

func previewRequest(key, path, token string) *http.Request {
	q := "/preview?key=" + key + "&path=" + path
	if token != "" {
		q += "&token=" + token
	}
	return httptest.NewRequest(http.MethodGet, q, nil)
}

func decodePreview(t *testing.T, body string) previewResponse {
	t.Helper()
	var resp previewResponse
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("decode response: %v (body %q)", err, body)
	}
	return resp
}

func TestHandlePreview_ServesMarkdownInsideDocDir(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, "notes.md", "# Title\n\nbody line\n")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, previewRequest("session-1", "notes.md", testToken))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	resp := decodePreview(t, w.Body.String())
	if resp.Name != "notes.md" {
		t.Fatalf("expected name notes.md, got %q", resp.Name)
	}
	if len(resp.Lines) < 3 || resp.Lines[0] != "# Title" || resp.Lines[2] != "body line" {
		t.Fatalf("unexpected lines: %#v", resp.Lines)
	}
	if resp.Truncated {
		t.Fatalf("a short file must not report truncation")
	}
}

func TestHandlePreview_ServesFileInSubdirectory(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, "sub/deep.txt", "hello\n")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, previewRequest("session-1", "sub%2Fdeep.txt", testToken))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if resp := decodePreview(t, w.Body.String()); resp.Lines[0] != "hello" {
		t.Fatalf("unexpected lines: %#v", resp.Lines)
	}
}

func TestHandlePreview_RejectsBadToken(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, "notes.md", "x")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, previewRequest("session-1", "notes.md", "wrong-token"))

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for a bad token, got %d", w.Code)
	}
}

// The whole point of the narrower allowlist: source files next to the
// document must NOT be readable through the hover preview.
func TestHandlePreview_RejectsNonTextExtension(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, "secret.lua", "local token = 'hunter2'")
	mustWriteFile(t, dir, "photo.png", "bytes")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handlePreview(registry, testToken)

	for _, name := range []string{"secret.lua", "photo.png", "notes.pdf"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, previewRequest("session-1", name, testToken))
		if w.Code != http.StatusForbidden {
			t.Fatalf("expected 403 for %q, got %d", name, w.Code)
		}
		if strings.Contains(w.Body.String(), "hunter2") {
			t.Fatalf("rejected response leaked file contents for %q", name)
		}
	}
}

func TestHandlePreview_RejectsPathTraversal(t *testing.T) {
	root := t.TempDir()
	docDir := mustMkdir(t, root, "doc")
	mustWriteFile(t, root, "outside.md", "secret-outside")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", docDir)

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, previewRequest("session-1", "..%2Foutside.md", testToken))

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for a traversal attempt, got %d", w.Code)
	}
	if strings.Contains(w.Body.String(), "secret-outside") {
		t.Fatalf("traversal response leaked contents outside the doc dir")
	}
}

func TestHandlePreview_RejectsUnknownSession(t *testing.T) {
	registry := relay.NewRegistry()

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, previewRequest("no-such-session", "notes.md", testToken))

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for an unknown session, got %d", w.Code)
	}
}

func TestHandlePreview_RejectsMissingParams(t *testing.T) {
	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", t.TempDir())

	h := handlePreview(registry, testToken)
	for _, q := range []string{"/preview?token=" + testToken, "/preview?key=session-1&token=" + testToken} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(http.MethodGet, q, nil))
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for %q, got %d", q, w.Code)
		}
	}
}

func TestHandlePreview_RejectsNonGet(t *testing.T) {
	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", t.TempDir())

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/preview?key=session-1&path=notes.md&token="+testToken, nil))

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405 for POST, got %d", w.Code)
	}
}

func TestHandlePreview_CapsLineCount(t *testing.T) {
	dir := t.TempDir()
	var b strings.Builder
	for i := 0; i < previewMaxLines*3; i++ {
		b.WriteString("line\n")
	}
	mustWriteFile(t, dir, "long.md", b.String())

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, previewRequest("session-1", "long.md", testToken))

	resp := decodePreview(t, w.Body.String())
	if len(resp.Lines) > previewMaxLines {
		t.Fatalf("expected at most %d lines, got %d", previewMaxLines, len(resp.Lines))
	}
	if !resp.Truncated {
		t.Fatalf("a capped file must report truncation")
	}
}

// A file larger than previewMaxBytes must be read partially, not slurped,
// and must still produce a well-formed response.
func TestHandlePreview_CapsBytesRead(t *testing.T) {
	dir := t.TempDir()
	// One line far longer than the byte cap: the line cap alone would not
	// bound this, so it exercises the byte cap specifically.
	mustWriteFile(t, dir, "huge.txt", strings.Repeat("x", previewMaxBytes*2))

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, previewRequest("session-1", "huge.txt", testToken))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	resp := decodePreview(t, w.Body.String())
	if !resp.Truncated {
		t.Fatalf("an over-cap file must report truncation")
	}
	if resp.Size != int64(previewMaxBytes*2) {
		t.Fatalf("expected the real size %d, got %d", previewMaxBytes*2, resp.Size)
	}
	total := 0
	for _, line := range resp.Lines {
		total += len(line)
	}
	if total > previewMaxBytes {
		t.Fatalf("returned more bytes (%d) than the read cap %d", total, previewMaxBytes)
	}
}

// CRLF files must not render stray carriage returns in the popup.
func TestHandlePreview_NormalizesCRLF(t *testing.T) {
	dir := t.TempDir()
	mustWriteFile(t, dir, "crlf.md", "# Title\r\n\r\nbody\r\n")

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, previewRequest("session-1", "crlf.md", testToken))

	resp := decodePreview(t, w.Body.String())
	for _, line := range resp.Lines {
		if strings.Contains(line, "\r") {
			t.Fatalf("carriage return survived normalization: %q", line)
		}
	}
	if resp.Lines[0] != "# Title" {
		t.Fatalf("unexpected first line: %q", resp.Lines[0])
	}
}

func TestHandlePreview_RejectsDirectory(t *testing.T) {
	dir := t.TempDir()
	mustMkdir(t, dir, "notes.md") // a directory that looks like a markdown file

	registry := relay.NewRegistry()
	registry.SetDocDir("session-1", dir)

	h := handlePreview(registry, testToken)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, previewRequest("session-1", "notes.md", testToken))

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for a directory, got %d", w.Code)
	}
}

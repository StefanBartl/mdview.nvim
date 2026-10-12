package source

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// ErrStale is returned by ReplaceLines when the lines in the file are no longer
// the ones the edit was made against: the preview was rendered from an older
// text. The edit is refused rather than applied to whatever happens to be there.
var ErrStale = errors.New("lines changed since the preview was rendered")

// writeMu serialises the read-modify-write cycles of the watched file inside
// this process (block edits, checkbox toggles and field edits all rewrite it):
// two requests that arrive together must not both start from the same content.
var writeMu sync.Mutex

// ReplaceLines replaces the 1-based, inclusive line range start..end of the file
// at `path` with `text`, but only if those lines currently equal `expected`.
//
// Everything outside the range is preserved byte for byte, including a file
// whose lines end differently (LF here, CRLF there): lines are split on "\n"
// alone, and a CRLF line keeps its "\r". New lines take the line ending of the
// first line they replace; the last of them keeps what the last replaced line
// had, so the document's own ending of that line (or its absence at the end of
// the file) survives. `expected` and `text` may use either line ending.
//
// If `path` is a symbolic link the file it points at is the one that is
// rewritten; the link stays a link. The file is replaced atomically (a temp file
// in the same folder, then a rename), so a reader — Neovim's autoread, the
// watcher — never sees half of it, and it is read once more right before the
// rename: if another program saved it in between, the edit is refused.
func ReplaceLines(path string, start, end int, expected, text string) error {
	if start < 1 || end < start {
		return fmt.Errorf("invalid line range %d-%d", start, end)
	}

	writeMu.Lock()
	defer writeMu.Unlock()

	target, err := filepath.EvalSymlinks(path)
	if err != nil {
		return err
	}
	content, err := os.ReadFile(target)
	if err != nil {
		return err
	}
	info, err := os.Stat(target)
	if err != nil {
		return err
	}

	raw := strings.Split(string(content), "\n") // a CRLF line keeps its "\r"
	if end > len(raw) {
		return ErrStale
	}

	current := make([]string, 0, end-start+1)
	for _, l := range raw[start-1 : end] {
		current = append(current, strings.TrimSuffix(l, "\r"))
	}
	if strings.Join(current, "\n") != strings.ReplaceAll(expected, "\r\n", "\n") {
		return ErrStale
	}

	// The first replaced line says which ending the block uses; an unterminated
	// last line has none of its own, so the file's decides.
	crlf := strings.HasSuffix(raw[start-1], "\r")
	if !crlf && start == len(raw) {
		crlf = bytes.Contains(content, []byte("\r\n"))
	}
	lineEnd := ""
	if crlf {
		lineEnd = "\r"
	}
	lastEnd := ""
	if strings.HasSuffix(raw[end-1], "\r") {
		lastEnd = "\r"
	}

	replacement := strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	out := make([]string, 0, len(raw)-(end-start+1)+len(replacement))
	out = append(out, raw[:start-1]...)
	for i, l := range replacement {
		if i < len(replacement)-1 {
			out = append(out, l+lineEnd)
		} else {
			out = append(out, l+lastEnd)
		}
	}
	out = append(out, raw[end:]...)

	// Another program may have saved the file since it was read.
	again, err := os.ReadFile(target)
	if err != nil {
		return err
	}
	if !bytes.Equal(again, content) {
		return ErrStale
	}

	return writeAtomic(target, []byte(strings.Join(out, "\n")), info.Mode().Perm())
}

// writeAtomic writes data next to `path` and renames it over the target.
func writeAtomic(path string, data []byte, perm os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".mdview-edit-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	cleanup := func() { _ = os.Remove(tmpName) }

	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		cleanup()
		return err
	}
	// Flushed before the rename: a crash must not leave a renamed, empty file.
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		cleanup()
		return err
	}
	if err := tmp.Close(); err != nil {
		cleanup()
		return err
	}
	if err := os.Chmod(tmpName, perm); err != nil {
		cleanup()
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		cleanup()
		return err
	}
	return nil
}

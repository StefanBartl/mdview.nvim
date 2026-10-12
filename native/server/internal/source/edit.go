package source

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ErrStale is returned by ReplaceLines when the lines in the file are no longer
// the ones the edit was made against: the preview was rendered from an older
// text. The edit is refused rather than applied to whatever happens to be there.
var ErrStale = errors.New("lines changed since the preview was rendered")

// ReplaceLines replaces the 1-based, inclusive line range start..end of the file
// at `path` with `text`, but only if those lines currently equal `expected`.
//
// The rest of the document is preserved byte for byte: the file's line ending
// (LF or CRLF) is detected and used for the replacement, and a trailing newline
// stays. `expected` and `text` may use either line ending; both are compared and
// written in the file's own.
//
// The file is replaced atomically (a temp file in the same folder, then a
// rename), so a reader — Neovim's autoread, the watcher — never sees half of it.
func ReplaceLines(path string, start, end int, expected, text string) error {
	if start < 1 || end < start {
		return fmt.Errorf("invalid line range %d-%d", start, end)
	}

	content, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	info, err := os.Stat(path)
	if err != nil {
		return err
	}

	newline := "\n"
	if strings.Contains(string(content), "\r\n") {
		newline = "\r\n"
	}
	lines := strings.Split(strings.ReplaceAll(string(content), "\r\n", "\n"), "\n")

	if end > len(lines) {
		return ErrStale
	}
	current := strings.Join(lines[start-1:end], "\n")
	if current != strings.ReplaceAll(expected, "\r\n", "\n") {
		return ErrStale
	}

	replacement := strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	out := make([]string, 0, len(lines)-(end-start+1)+len(replacement))
	out = append(out, lines[:start-1]...)
	out = append(out, replacement...)
	out = append(out, lines[end:]...)

	return writeAtomic(path, []byte(strings.Join(out, newline)), info.Mode().Perm())
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

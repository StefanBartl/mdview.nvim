package source

import (
	"bytes"
	"fmt"
	"strings"
)

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
// rewritten; the link stays a link. The file is replaced atomically (see
// writeThrough), refused when another program saved it in between (ErrStale),
// and a read-only file is not touched (ErrReadOnly).
func ReplaceLines(path string, start, end int, expected, text string) error {
	if start < 1 || end < start {
		return fmt.Errorf("invalid line range %d-%d", start, end)
	}

	writeMu.Lock()
	defer writeMu.Unlock()

	target, content, perm, err := loadWatched(path)
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

	return writeThrough(target, []byte(strings.Join(out, "\n")), content, perm)
}

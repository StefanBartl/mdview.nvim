package source

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

// taskMarker matches a GFM task-list item's checkbox marker at the start of a
// line: optional indent, a bullet (-, * or +), a space, then "[ ]" / "[x]" /
// "[X]". The three capture groups are (everything up to and including the
// opening bracket), (the state char), (everything from the closing bracket on),
// so flipping is a single-character rewrite that preserves indentation, bullet
// style and the item text exactly.
var taskMarker = regexp.MustCompile(`^(\s*[-*+] \[)([ xX])(\].*)$`)

// ToggleCheckbox flips the task-list checkbox on 1-based line `line` of the file
// at `path` to `checked`, writing the file back in place. It is a no-op (nil
// error) when the line doesn't hold a task marker — a re-render can briefly race
// a rapid edit, and refusing to write garbage is safer than trusting a stale
// line number.
//
// Only the one marker character changes; the rest of the line, the line ending,
// and every other line are preserved exactly, so a checkbox toggle never
// reformats the user's document.
func ToggleCheckbox(path string, line int, checked bool) error {
	if line < 1 {
		return fmt.Errorf("invalid line %d", line)
	}

	content, err := os.ReadFile(path)
	if err != nil {
		return err
	}

	// Detect and preserve the file's line ending; split on "\n" after
	// normalizing so a lone marker rewrite doesn't flip CRLF to LF elsewhere.
	newline := "\n"
	if strings.Contains(string(content), "\r\n") {
		newline = "\r\n"
	}
	lines := strings.Split(strings.ReplaceAll(string(content), "\r\n", "\n"), "\n")

	if line > len(lines) {
		// Stale line number (file shrank since render) — decline silently.
		return nil
	}

	m := taskMarker.FindStringSubmatch(lines[line-1])
	if m == nil {
		// Not a checkbox line — decline rather than corrupt it.
		return nil
	}

	want := " "
	if checked {
		want = "x"
	}
	if m[2] == want {
		return nil // already in the requested state; no write
	}
	lines[line-1] = m[1] + want + m[3]

	return os.WriteFile(path, []byte(strings.Join(lines, newline)), 0o644)
}

package source

import (
	"fmt"
	"regexp"
	"strings"
)

// taskMarker matches a GFM task-list item's checkbox marker at the start of a
// line: optional indent, a bullet (-, * or +), a space, then "[ ]" / "[x]" /
// "[X]". The three capture groups are (everything up to and including the
// opening bracket), (the state char), (everything from the closing bracket on),
// so flipping is a single-character rewrite that preserves indentation, bullet
// style and the item text exactly. It is matched against a line without its
// trailing "\r".
var taskMarker = regexp.MustCompile(`^(\s*[-*+] \[)([ xX])(\].*)$`)

// ToggleCheckbox flips the task-list checkbox on 1-based line `line` of the file
// at `path` to `checked`, writing the file back in place. It is a no-op (nil
// error) when the line doesn't hold a task marker — a re-render can briefly race
// a rapid edit, and refusing to write garbage is safer than trusting a stale
// line number.
//
// Only the one marker character changes; the rest of the line, the line ending,
// and every other line are preserved exactly (also in a file whose lines end
// differently), so a checkbox toggle never reformats the user's document.
func ToggleCheckbox(path string, line int, checked bool) error {
	return ToggleCheckboxIf(path, line, checked, "")
}

// ToggleCheckboxIf is ToggleCheckbox that, when `expected` is not empty, also
// requires line `line` to hold exactly that text (without its line ending):
// the browser computed the line number from the render it was looking at, and
// an edit applied in between (a text field that gained lines, a block edit) may
// have moved it. A different line is ErrStale instead of toggling a neighbour.
func ToggleCheckboxIf(path string, line int, checked bool, expected string) error {
	if line < 1 {
		return fmt.Errorf("invalid line %d", line)
	}

	writeMu.Lock()
	defer writeMu.Unlock()

	target, content, perm, err := loadWatched(path)
	if err != nil {
		return err
	}

	lines := strings.Split(string(content), "\n") // a CRLF line keeps its "\r"
	if line > len(lines) {
		// Stale line number (file shrank since render) — decline silently.
		return nil
	}

	text := strings.TrimSuffix(lines[line-1], "\r")
	if expected != "" && text != strings.TrimSuffix(expected, "\r") {
		return ErrStale
	}

	m := taskMarker.FindStringSubmatch(text)
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
	lines[line-1] = m[1] + want + m[3] + strings.TrimPrefix(lines[line-1], text)

	return writeThrough(target, []byte(strings.Join(lines, "\n")), content, perm)
}

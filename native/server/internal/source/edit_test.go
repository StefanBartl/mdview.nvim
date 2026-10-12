package source

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestReplaceLines_ReplacesOneLine(t *testing.T) {
	path := writeTemp(t, "# Title\n\nold paragraph\n\nend\n")
	if err := ReplaceLines(path, 3, 3, "old paragraph", "new paragraph"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "# Title\n\nnew paragraph\n\nend\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestReplaceLines_ChangesLineCount(t *testing.T) {
	path := writeTemp(t, "a\nb\nc\nd\n")
	if err := ReplaceLines(path, 2, 3, "b\nc", "x\ny\nz"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "a\nx\ny\nz\nd\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
	// and back to fewer lines
	if err := ReplaceLines(path, 2, 4, "x\ny\nz", "q"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "a\nq\nd\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestReplaceLines_PreservesCRLFAndTrailingNewline(t *testing.T) {
	path := writeTemp(t, "one\r\ntwo\r\nthree\r\n")
	// expected/text may come with LF from the browser
	if err := ReplaceLines(path, 2, 2, "two", "2\n2b"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "one\r\n2\r\n2b\r\nthree\r\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestReplaceLines_StaleExpectedIsRefusedAndFileUntouched(t *testing.T) {
	path := writeTemp(t, "a\nb\nc\n")
	err := ReplaceLines(path, 2, 2, "not b", "x")
	if !errors.Is(err, ErrStale) {
		t.Fatalf("err = %v, want ErrStale", err)
	}
	if got, want := read(t, path), "a\nb\nc\n"; got != want {
		t.Fatalf("file changed: %q", got)
	}
}

func TestReplaceLines_RangePastTheEndIsStale(t *testing.T) {
	path := writeTemp(t, "a\nb\n")
	if err := ReplaceLines(path, 5, 6, "x", "y"); !errors.Is(err, ErrStale) {
		t.Fatalf("err = %v, want ErrStale", err)
	}
}

func TestReplaceLines_InvalidRange(t *testing.T) {
	path := writeTemp(t, "a\n")
	if err := ReplaceLines(path, 0, 1, "a", "b"); err == nil {
		t.Fatal("start 0 must be refused")
	}
	if err := ReplaceLines(path, 2, 1, "a", "b"); err == nil {
		t.Fatal("end before start must be refused")
	}
}

func TestReplaceLines_LeavesNoTempFileBehind(t *testing.T) {
	path := writeTemp(t, "a\nb\n")
	if err := ReplaceLines(path, 1, 1, "a", "z"); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Fatalf("folder holds %d entries, want only the file", len(entries))
	}
}

func TestReplaceLines_MixedLineEndingsAreKeptByteForByte(t *testing.T) {
	path := writeTemp(t, "lf one\nlf two\r\ncrlf three\r\nlf four\n")
	if err := ReplaceLines(path, 3, 3, "crlf three", "3a\n3b"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "lf one\nlf two\r\n3a\r\n3b\r\nlf four\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
	// an LF block inside a CRLF file stays LF
	path = writeTemp(t, "crlf one\r\nlf two\nlf three\ncrlf four\r\n")
	if err := ReplaceLines(path, 2, 3, "lf two\nlf three", "x\ny\nz"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "crlf one\r\nx\ny\nz\ncrlf four\r\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestReplaceLines_LastLineWithoutNewlineKeepsItsAbsence(t *testing.T) {
	path := writeTemp(t, "a\nb")
	if err := ReplaceLines(path, 2, 2, "b", "c\nd"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "a\nc\nd"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestReplaceLines_WritesThroughASymlink(t *testing.T) {
	dir := t.TempDir()
	real := filepath.Join(dir, "real.md")
	if err := os.WriteFile(real, []byte("a\nold\nb\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link.md")
	if err := os.Symlink(real, link); err != nil {
		t.Skipf("symlinks not available here: %v", err)
	}

	if err := ReplaceLines(link, 2, 2, "old", "new"); err != nil {
		t.Fatal(err)
	}
	info, err := os.Lstat(link)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode()&os.ModeSymlink == 0 {
		t.Fatal("the link was replaced by a regular file")
	}
	if got, want := read(t, real), "a\nnew\nb\n"; got != want {
		t.Fatalf("target = %q, want %q", got, want)
	}
}

func TestReplaceLines_ConcurrentEditsOfDifferentLinesAreAllKept(t *testing.T) {
	var sb strings.Builder
	for i := 0; i < 20; i++ {
		fmt.Fprintf(&sb, "line %d\n", i)
	}
	path := writeTemp(t, sb.String())

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			old := fmt.Sprintf("line %d", i)
			if err := ReplaceLines(path, i+1, i+1, old, old+" edited"); err != nil {
				t.Errorf("line %d: %v", i, err)
			}
		}(i)
	}
	wg.Wait()

	for i, l := range strings.Split(strings.TrimSuffix(read(t, path), "\n"), "\n") {
		if want := fmt.Sprintf("line %d edited", i); l != want {
			t.Fatalf("line %d = %q, want %q (a concurrent edit was lost)", i+1, l, want)
		}
	}
}

// A hard link is not a symlink: the file is replaced by a rename, so the edited
// name gets the new content and the other name keeps the old one (the link is
// split). This pins that documented limitation (docs/PREVIEW.md, "Editing
// blocks") so a change in it is a decision, not an accident.
func TestReplaceLines_SplitsAHardLink(t *testing.T) {
	path := writeTemp(t, "a\nb\nc\n")
	other := path + ".link"
	if err := os.Link(path, other); err != nil {
		t.Skipf("hard links not available here: %v", err)
	}
	if err := ReplaceLines(path, 2, 2, "b", "B"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "a\nB\nc\n"; got != want {
		t.Fatalf("edited name: got %q want %q", got, want)
	}
	if got, want := read(t, other), "a\nb\nc\n"; got != want {
		t.Fatalf("other name keeps the old text: got %q want %q", got, want)
	}
}

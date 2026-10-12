package source

import (
	"errors"
	"os"
	"path/filepath"
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

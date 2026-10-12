package source

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// A program that saves the file between the last read and the rename must win:
// the edit is refused, the other program's text stays, no temp file is left.
func TestReplaceLines_FileSavedByAnotherProgramBeforeTheRenameIsKept(t *testing.T) {
	path := writeTemp(t, "a\nold\nb\n")
	external := "a\nsomeone else wrote this\nb\n"

	beforeRename = func() {
		if err := os.WriteFile(path, []byte(external), 0o644); err != nil {
			t.Error(err)
		}
	}
	defer func() { beforeRename = nil }()

	err := ReplaceLines(path, 2, 2, "old", "mine")
	if !errors.Is(err, ErrStale) {
		t.Fatalf("err = %v, want ErrStale", err)
	}
	if got := read(t, path); got != external {
		t.Fatalf("the other program's save was overwritten: %q", got)
	}
	entries, _ := os.ReadDir(filepath.Dir(path))
	if len(entries) != 1 {
		t.Fatalf("folder holds %d entries, want only the file (a temp file was left)", len(entries))
	}
}

func TestReplaceLines_ReadOnlyFileIsNotRewritten(t *testing.T) {
	path := writeTemp(t, "a\nold\nb\n")
	if err := os.Chmod(path, 0o444); err != nil {
		t.Skipf("cannot make the file read-only here: %v", err)
	}
	defer func() { _ = os.Chmod(path, 0o644) }()

	err := ReplaceLines(path, 2, 2, "old", "new")
	if !errors.Is(err, ErrReadOnly) {
		t.Fatalf("err = %v, want ErrReadOnly", err)
	}
	if got, want := read(t, path), "a\nold\nb\n"; got != want {
		t.Fatalf("file changed: %q", got)
	}
}

func TestReplaceLines_CRLFFileWithUnterminatedLastLine(t *testing.T) {
	path := writeTemp(t, "a\r\nb")
	if err := ReplaceLines(path, 2, 2, "b", "c\nd"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "a\r\nc\r\nd"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestReplaceLines_EmptyFileAndNewlineOnlyFile(t *testing.T) {
	path := writeTemp(t, "")
	if err := ReplaceLines(path, 1, 1, "", "first"); err != nil {
		t.Fatal(err)
	}
	if got := read(t, path); got != "first" {
		t.Fatalf("empty file: got %q", got)
	}
	path = writeTemp(t, "\n")
	if err := ReplaceLines(path, 1, 1, "", "x"); err != nil {
		t.Fatal(err)
	}
	if got := read(t, path); got != "x\n" {
		t.Fatalf("newline-only file: got %q", got)
	}
}

func TestToggleCheckbox_KeepsEveryOtherLineEndingOfAMixedFile(t *testing.T) {
	path := writeTemp(t, "- [ ] a\n- [ ] b\r\nplain\nmore\n")
	if err := ToggleCheckbox(path, 1, true); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "- [x] a\n- [ ] b\r\nplain\nmore\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
	// a CRLF line keeps its "\r"
	if err := ToggleCheckbox(path, 2, true); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "- [x] a\n- [x] b\r\nplain\nmore\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestToggleCheckboxIf_ADifferentLineIsStaleAndNothingChanges(t *testing.T) {
	path := writeTemp(t, "- [ ] one\n- [ ] two\n")
	// the browser meant "two", but an edit moved the lines: line 1 is "one" now
	err := ToggleCheckboxIf(path, 1, true, "- [ ] two")
	if !errors.Is(err, ErrStale) {
		t.Fatalf("err = %v, want ErrStale", err)
	}
	if got, want := read(t, path), "- [ ] one\n- [ ] two\n"; got != want {
		t.Fatalf("file changed: %q", got)
	}
	if err := ToggleCheckboxIf(path, 2, true, "- [ ] two\r"); err != nil {
		t.Fatalf("a matching expected line (even with a \\r) must apply: %v", err)
	}
	if got, want := read(t, path), "- [ ] one\n- [x] two\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_NameNeedsABoundaryAndWritesThroughASymlink(t *testing.T) {
	dir := t.TempDir()
	real := filepath.Join(dir, "real.md")
	src := `<input username="title">` + "\n" + `<input data-name="title">` + "\n" + `<input name="title">` + "\n"
	if err := os.WriteFile(real, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link.md")
	linked := os.Symlink(real, link) == nil
	target := real
	if linked {
		target = link
	}

	if err := SetFieldValue(target, "title", "X"); err != nil {
		t.Fatal(err)
	}
	want := `<input username="title">` + "\n" + `<input data-name="title">` + "\n" + `<input name="title" value="X">` + "\n"
	if got := read(t, real); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
	if linked {
		info, err := os.Lstat(link)
		if err != nil || info.Mode()&os.ModeSymlink == 0 {
			t.Fatal("the link was replaced by a regular file")
		}
	}
}

// The watcher reads the file; an edit renames over it. On Windows that fails
// against an open handle, so the watcher reads under the lock and the edit
// retries: no edit may fail just because the poller happened to be reading.
func TestReplaceLines_NeverFailsBecauseTheWatcherIsReading(t *testing.T) {
	var sb strings.Builder
	for i := 0; i < 50; i++ {
		fmt.Fprintf(&sb, "line %d\n", i)
	}
	path := writeTemp(t, sb.String())

	stop := make(chan struct{})
	done := make(chan struct{})
	go func() {
		defer close(done)
		Watch(&fakeBroadcaster{}, "k", path, 2*time.Millisecond, stop)
	}()
	defer func() {
		close(stop)
		<-done
	}()

	for i := 0; i < 60; i++ {
		cur := read(t, path)
		lines := strings.Split(cur, "\n")
		n := i % 50
		if err := ReplaceLines(path, n+1, n+1, lines[n], lines[n]+"+"); err != nil {
			t.Fatalf("edit %d failed: %v", i, err)
		}
	}
}

package source

import (
	"errors"
	"io/fs"
	"os"
	"strings"
	"testing"
)

// useInPlace makes createTemp refuse for permission, so writes go in place.
func useInPlace(t *testing.T) {
	t.Helper()
	old := createTemp
	createTemp = func(string, string) (*os.File, error) { return nil, fs.ErrPermission }
	t.Cleanup(func() { createTemp = old })
}

// A write that fails halfway leaves the old text, whether the new text was
// shorter or longer than it.
func TestWriteInPlace_FailedWriteRestoresTheOriginal(t *testing.T) {
	for _, tc := range []struct{ name, src string }{
		{"new text longer", "- [ ] a\n"},
		{"new text shorter", "- [ ] a very long first line of the document\n- [ ] b\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			useInPlace(t)
			path := writeTemp(t, tc.src)
			boom := errors.New("disk full")
			old := writeAt
			writeAt = func(f *os.File, data []byte) error {
				_, _ = f.WriteAt(data[:len(data)/2], 0) // half of it got there
				return boom
			}
			defer func() { writeAt = old }()

			if err := ToggleCheckbox(path, 1, true); !errors.Is(err, boom) {
				t.Fatalf("err = %v, want the write error", err)
			}
			if got := read(t, path); got != tc.src {
				t.Fatalf("the original was not put back: %q", got)
			}
		})
	}
}

// Another program's save between the caller's read and the write is kept: the
// same handle compares and replaces, and it never truncates before comparing.
func TestWriteInPlace_ForeignSaveIsNotCutOff(t *testing.T) {
	useInPlace(t)
	path := writeTemp(t, "- [ ] a\n")
	external := "- [ ] a\nsomeone else added this line\n"
	beforeRename = func() { _ = os.WriteFile(path, []byte(external), 0o644) }
	defer func() { beforeRename = nil }()

	if err := ToggleCheckbox(path, 1, true); !errors.Is(err, ErrStale) {
		t.Fatalf("err = %v, want ErrStale", err)
	}
	if got := read(t, path); got != external {
		t.Fatalf("the other program's save was changed: %q", got)
	}
}

func TestWriteInPlace_ShorterAndLongerResultsHaveTheRightLength(t *testing.T) {
	useInPlace(t)
	path := writeTemp(t, "- [ ] a\n"+strings.Repeat("x", 100)+"\n")
	if err := ToggleCheckbox(path, 1, true); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "- [x] a\n"+strings.Repeat("x", 100)+"\n"; got != want {
		t.Fatalf("got %q", got)
	}
	// replace by something much shorter
	if err := ReplaceLines(path, 2, 2, strings.Repeat("x", 100), "y"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "- [x] a\ny\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

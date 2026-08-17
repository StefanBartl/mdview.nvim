package source

import (
	"os"
	"path/filepath"
	"testing"
)

func writeTemp(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "doc.md")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func read(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestToggleCheckbox_ChecksAnUncheckedBox(t *testing.T) {
	path := writeTemp(t, "# T\n\n- [ ] alpha\n- [ ] beta\n")
	if err := ToggleCheckbox(path, 3, true); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "# T\n\n- [x] alpha\n- [ ] beta\n"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestToggleCheckbox_UnchecksAndPreservesText(t *testing.T) {
	path := writeTemp(t, "- [x] done thing\n")
	if err := ToggleCheckbox(path, 1, false); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "- [ ] done thing\n"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestToggleCheckbox_PreservesIndentAndBulletStyle(t *testing.T) {
	path := writeTemp(t, "- [ ] parent\n  * [ ] nested star\n")
	if err := ToggleCheckbox(path, 2, true); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "- [ ] parent\n  * [x] nested star\n"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestToggleCheckbox_PreservesCRLF(t *testing.T) {
	path := writeTemp(t, "- [ ] a\r\n- [ ] b\r\n")
	if err := ToggleCheckbox(path, 2, true); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "- [ ] a\r\n- [x] b\r\n"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestToggleCheckbox_NoOpWhenAlreadyInState(t *testing.T) {
	path := writeTemp(t, "- [x] already\n")
	before, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := ToggleCheckbox(path, 1, true); err != nil {
		t.Fatal(err)
	}
	if read(t, path) != "- [x] already\n" {
		t.Fatal("content changed on a no-op toggle")
	}
	_ = before
}

func TestToggleCheckbox_DeclinesNonCheckboxLine(t *testing.T) {
	path := writeTemp(t, "# heading\n\njust a paragraph\n")
	if err := ToggleCheckbox(path, 3, true); err != nil {
		t.Fatal(err)
	}
	if read(t, path) != "# heading\n\njust a paragraph\n" {
		t.Fatal("a non-checkbox line was modified")
	}
}

func TestToggleCheckbox_DeclinesStaleLineNumber(t *testing.T) {
	path := writeTemp(t, "- [ ] only line\n")
	if err := ToggleCheckbox(path, 99, true); err != nil {
		t.Fatal(err)
	}
	if read(t, path) != "- [ ] only line\n" {
		t.Fatal("content changed for an out-of-range line")
	}
}

func TestToggleCheckbox_RejectsInvalidLine(t *testing.T) {
	path := writeTemp(t, "- [ ] a\n")
	if err := ToggleCheckbox(path, 0, true); err == nil {
		t.Fatal("expected an error for line 0")
	}
}

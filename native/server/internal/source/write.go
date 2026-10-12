package source

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"
)

// ErrStale is returned when the lines (or the file) are no longer the ones an
// edit was made against: the preview was rendered from an older text, or
// another program saved the file in between. The edit is refused rather than
// applied to whatever happens to be there.
var ErrStale = errors.New("lines changed since the preview was rendered")

// ErrReadOnly is returned for a file whose owner-write bit is off. Replacing it
// by rename would succeed on Unix anyway, so the check is explicit: a write
// protected document is not rewritten by a browser click.
var ErrReadOnly = errors.New("file is read-only")

// writeMu serialises the read-modify-write cycles of the watched file inside
// this process (block edits, checkbox toggles and field edits all rewrite it).
// Two requests that arrive together must not both start from the same content,
// and the poller that watches the file reads it under the read lock, so it never
// holds the file open while a rewrite renames over it (on Windows that rename
// fails against any open handle).
var writeMu sync.RWMutex

// beforeRename is a test seam: called after the temp file is complete and
// right before the last check of the target and the rename.
var beforeRename func()

// loadWatched resolves `path` (a symbolic link is followed: the file it points
// at is the document), checks it may be rewritten, and reads it. The caller
// holds writeMu.
func loadWatched(path string) (target string, content []byte, perm os.FileMode, err error) {
	target, err = filepath.EvalSymlinks(path)
	if err != nil {
		return "", nil, 0, err
	}
	info, err := os.Stat(target)
	if err != nil {
		return "", nil, 0, err
	}
	if info.IsDir() {
		return "", nil, 0, fmt.Errorf("%s is a directory", target)
	}
	if info.Size() > maxFileBytes {
		return "", nil, 0, fmt.Errorf("file is %d bytes, over the %d byte limit", info.Size(), maxFileBytes)
	}
	if info.Mode().Perm()&0o200 == 0 {
		return "", nil, 0, fmt.Errorf("%w: %s", ErrReadOnly, target)
	}
	content, err = os.ReadFile(target)
	if err != nil {
		return "", nil, 0, err
	}
	return target, content, info.Mode().Perm(), nil
}

// writeThrough replaces `target` with `data` atomically: a temp file in the same
// folder, flushed, then renamed over it, so a reader never sees half of it.
//
// `original` is what the caller read and based `data` on. It is compared with
// the file once more as the last step before the rename; if another program
// saved the file meanwhile the write is refused with ErrStale. That narrows the
// window to the rename itself — without file locking it cannot be closed.
func writeThrough(target string, data, original []byte, perm os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(target), ".mdview-edit-*")
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

	if beforeRename != nil {
		beforeRename()
	}
	again, err := os.ReadFile(target)
	if err != nil {
		cleanup()
		return err
	}
	if !bytes.Equal(again, original) {
		cleanup()
		return ErrStale
	}

	if err := renameReplacing(tmpName, target); err != nil {
		cleanup()
		return err
	}
	return nil
}

// renameReplacing renames over an existing file. On Windows the rename fails
// while any other program has the target open without share-delete (a virus
// scanner, an indexer, a sync client, an editor's file watcher), usually for a
// few milliseconds; it is retried briefly before giving up.
func renameReplacing(from, to string) error {
	attempts := 1
	if runtime.GOOS == "windows" {
		attempts = 6
	}
	var err error
	for i := 0; i < attempts; i++ {
		if err = os.Rename(from, to); err == nil {
			return nil
		}
		if i < attempts-1 {
			time.Sleep(time.Duration(25*(i+1)) * time.Millisecond)
		}
	}
	return err
}

package source

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
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
// the file once more as the last step before every rename attempt; if another
// program saved the file meanwhile the write is refused with ErrStale. That
// narrows the window to the rename itself — without file locking it cannot be
// closed. When the folder takes no new file, the document is rewritten in place
// instead (see writeInPlace): the same comparison, but not atomic.
func writeThrough(target string, data, original []byte, perm os.FileMode) error {
	tmp, err := createTemp(filepath.Dir(target), ".mdview-edit-*")
	if err != nil {
		// The folder cannot take a new file (read-only folder, a share without
		// create rights) although the document itself is writable: write it in
		// place. Not atomic — a reader may see it half written — but the same
		// comparison with `original` still applies.
		return writeInPlace(target, data, original)
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

	if err := renameReplacing(tmpName, target, original); err != nil {
		cleanup()
		return err
	}
	return nil
}

// Test seams for the rename retry.
var (
	createTemp       = os.CreateTemp
	renameFile       = os.Rename
	isRetryableError = isSharingViolation
	retryDelays      = []time.Duration{10 * time.Millisecond, 20 * time.Millisecond, 40 * time.Millisecond}
)

// sameAsOriginal reports whether the file at `target` still holds `original`.
func sameAsOriginal(target string, original []byte) error {
	again, err := os.ReadFile(target)
	if err != nil {
		return err
	}
	if !bytes.Equal(again, original) {
		return ErrStale
	}
	return nil
}

// renameReplacing renames over an existing file. On Windows the rename fails
// while any other program has the target open without share-delete (a virus
// scanner, an indexer, a sync client, an editor's file watcher), usually for a
// few milliseconds. Only such a sharing error is retried (briefly: writeMu is
// held meanwhile), and every attempt first compares the file with `original`
// again, as another program may have saved it while this one waited. Any other
// error, a missing target included, ends it at once.
func renameReplacing(from, to string, original []byte) error {
	for i := 0; ; i++ {
		if beforeRename != nil {
			beforeRename()
		}
		if err := sameAsOriginal(to, original); err != nil {
			return err
		}
		err := renameFile(from, to)
		if err == nil {
			return nil
		}
		if i >= len(retryDelays) || !isRetryableError(err) {
			return err
		}
		time.Sleep(retryDelays[i])
	}
}

// writeInPlace is writeThrough for a folder that takes no new file: compare,
// then rewrite the document itself.
func writeInPlace(target string, data, original []byte) error {
	if beforeRename != nil {
		beforeRename()
	}
	if err := sameAsOriginal(target, original); err != nil {
		return err
	}
	// Never create: the file was there a moment ago, and a vanished one is not
	// to be resurrected with an arbitrary mode.
	f, err := os.OpenFile(target, os.O_WRONLY|os.O_TRUNC, 0)
	if err != nil {
		return err
	}
	if _, err := f.Write(data); err != nil {
		_ = f.Close()
		return err
	}
	return f.Close()
}

// Package source provides content sources for the relay: alternatives to the
// token-gated POST /update endpoint that the Neovim plugin drives.
//
// The relay itself knows nothing about files — it only knows "here is text for
// room key K, fan it out". That is what makes standalone mode cheap: a file
// watcher reads the file and calls the exact same registry.Broadcast the HTTP
// handler calls, so the browser client, the WebSocket framing and the WASM
// renderer are all reached through the unchanged code path and need no
// awareness that Neovim isn't involved.
package source

import (
	"bytes"
	"fmt"
	"os"
	"time"
)

// Broadcaster is the slice of *relay.Registry a watcher needs. Kept as an
// interface so the watcher can be tested without a registry or a network.
type Broadcaster interface {
	Broadcast(key string, payload []byte) []error
}

// DefaultInterval is how often Watch stats the file. Polling rather than
// fsnotify is deliberate: watching exactly one file at ~4 Hz costs nothing
// measurable, behaves identically on Linux/macOS/Windows, and avoids adding a
// dependency (and its platform-specific edge cases around editors that write
// via rename-over, which every serious editor does and which breaks naive
// inotify watches on the original inode).
const DefaultInterval = 250 * time.Millisecond

// maxFileBytes mirrors the relay's /update ceiling, so a runaway file can't
// balloon the process's memory any more than a runaway POST could.
const maxFileBytes = 32 << 20

// Watch polls path and broadcasts its contents to room `key` whenever they
// change, until stop is closed. It broadcasts once immediately so a browser tab
// that connects before the first change still gets content.
//
// A read error is reported once and then retried silently: the common cause is
// an editor writing via a temp file and renaming over the target, during which
// the path is briefly absent. Treating that as fatal would kill a standalone
// preview on the user's very first save.
func Watch(b Broadcaster, key, path string, interval time.Duration, stop <-chan struct{}) {
	if interval <= 0 {
		interval = DefaultInterval
	}

	var last []byte
	var reportedErr bool

	read := func() {
		content, err := readCapped(path)
		if err != nil {
			if !reportedErr {
				fmt.Printf("[watch] cannot read %s: %v (retrying)\n", path, err)
				reportedErr = true
			}
			return
		}
		if reportedErr {
			fmt.Printf("[watch] recovered: %s\n", path)
			reportedErr = false
		}
		// Compare content, not mtime: mtime granularity is coarse enough on
		// some filesystems that two saves within the same tick would look
		// identical, and a no-op save shouldn't cost a full re-render.
		if last != nil && bytes.Equal(last, content) {
			return
		}
		last = content
		b.Broadcast(key, content)
	}

	read()

	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			read()
		}
	}
}

// readCapped reads path, refusing anything past maxFileBytes rather than
// loading an arbitrarily large file into memory.
func readCapped(path string) ([]byte, error) {
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if info.IsDir() {
		return nil, fmt.Errorf("is a directory")
	}
	if info.Size() > maxFileBytes {
		return nil, fmt.Errorf("file is %d bytes, over the %d byte limit", info.Size(), maxFileBytes)
	}
	return os.ReadFile(path)
}

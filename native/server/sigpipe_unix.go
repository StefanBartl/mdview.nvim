//go:build !windows

package main

import (
	"os/signal"
	"syscall"
)

// ignoreSIGPIPE keeps a shared relay alive when the Neovim instance that
// spawned it exits: its stdout is a pipe to that instance, and without this the
// next log line would kill the process with SIGPIPE.
func ignoreSIGPIPE() {
	signal.Ignore(syscall.SIGPIPE)
}

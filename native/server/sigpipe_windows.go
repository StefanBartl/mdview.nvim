//go:build windows

package main

// ignoreSIGPIPE is a no-op on Windows: a write to a pipe whose reader is gone
// fails with an error there, it does not end the process.
func ignoreSIGPIPE() {}

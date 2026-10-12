//go:build !windows

package source

// isSharingViolation is always false off Windows: a rename over an open file
// succeeds there, so a failed rename is a real failure and is not retried.
func isSharingViolation(error) bool { return false }

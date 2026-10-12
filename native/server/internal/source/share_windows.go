//go:build windows

package source

import (
	"errors"
	"syscall"
)

// Win32 errors a rename over a file reports while another program has it open
// without share-delete: ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION and
// ERROR_LOCK_VIOLATION. Anything else (a missing file included) is not waited for.
const (
	errorAccessDenied     syscall.Errno = 5
	errorSharingViolation syscall.Errno = 32
	errorLockViolation    syscall.Errno = 33
)

func isSharingViolation(err error) bool {
	var errno syscall.Errno
	if !errors.As(err, &errno) {
		return false
	}
	return errno == errorAccessDenied || errno == errorSharingViolation || errno == errorLockViolation
}

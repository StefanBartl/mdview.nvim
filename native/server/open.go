package main

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
)

// openBrowser opens url in the user's default browser.
//
// Only used in standalone (--watch) mode. In the normal Neovim-driven mode the
// Lua side owns browser opening (mdview.adapter.browser), including the
// isolated-profile and focus handling this deliberately does not replicate —
// standalone mode's contract is just "open a tab in whatever the default is".
//
// $BROWSER is honored on Unix because that is the established convention there
// and the only way a headless-ish/WSL user can redirect the tab somewhere
// reachable.
func openBrowser(url string) error {
	var cmd *exec.Cmd
	switch {
	case runtime.GOOS != "windows" && os.Getenv("BROWSER") != "":
		cmd = exec.Command(os.Getenv("BROWSER"), url)
	case runtime.GOOS == "windows":
		// Via rundll32 rather than `cmd /c start`, which mangles URLs
		// containing `&` (ours always does — ?key=...&token=...).
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	case runtime.GOOS == "darwin":
		cmd = exec.Command("open", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to open browser: %w", err)
	}
	// Reap the child rather than leaving a zombie; we don't care about its exit.
	go func() { _ = cmd.Wait() }()
	return nil
}

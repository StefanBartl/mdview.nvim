package relay

import "sync"

// ScrollHint is the browser's latest scroll position in a previewed document:
// the room key and a 0..1 ratio of how far down the view is. Only the most
// recent one matters (a scroll position is superseded, not accumulated), so
// unlike NavQueue this is a single-slot mailbox, not a FIFO.
type ScrollHint struct {
	Key   string  `json:"key"`
	Ratio float64 `json:"ratio"`
}

// ScrollBox holds the latest browser->Neovim scroll hint. The client overwrites
// it as the user scrolls (POST /scrollback); Neovim consumes it by polling
// (GET /scrollback), which clears it so the same position isn't re-applied and
// made to fight the user's own cursor.
type ScrollBox struct {
	mu   sync.Mutex
	hint *ScrollHint
}

func NewScrollBox() *ScrollBox {
	return &ScrollBox{}
}

// Set overwrites the pending hint with the newest scroll position.
func (b *ScrollBox) Set(h ScrollHint) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.hint = &h
}

// Take returns the pending hint (or nil) and clears it, so each hint is
// consumed at most once.
func (b *ScrollBox) Take() *ScrollHint {
	b.mu.Lock()
	defer b.mu.Unlock()
	h := b.hint
	b.hint = nil
	return h
}

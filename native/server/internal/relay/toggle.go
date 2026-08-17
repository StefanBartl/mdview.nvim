package relay

import "sync"

// ToggleRequest is a single "the user ticked a task-list checkbox in the
// preview" event: the room key it happened in (the previewed document's path),
// the 1-based source line of the checkbox, and its new state. In standalone
// mode the relay applies this to the watched file itself; in Neovim-driven mode
// it only carries the event to Neovim, which edits the buffer (which may hold
// unsaved changes the relay must not clobber).
type ToggleRequest struct {
	Key     string `json:"key"`
	Line    int    `json:"line"`
	Checked bool   `json:"checked"`
}

// ToggleQueue is a tiny thread-safe FIFO of pending checkbox toggles, drained by
// Neovim's inbound poller — the same pattern as NavQueue. Bounded so a client
// that toggles rapidly while Neovim isn't polling can't grow it without limit.
type ToggleQueue struct {
	mu    sync.Mutex
	items []ToggleRequest
}

const maxToggleQueue = 256

func NewToggleQueue() *ToggleQueue {
	return &ToggleQueue{}
}

// Push appends a request, dropping the oldest if the queue is at capacity.
func (q *ToggleQueue) Push(r ToggleRequest) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.items) >= maxToggleQueue {
		q.items = q.items[1:]
	}
	q.items = append(q.items, r)
}

// Drain returns all pending requests and empties the queue.
func (q *ToggleQueue) Drain() []ToggleRequest {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.items) == 0 {
		return nil
	}
	out := q.items
	q.items = nil
	return out
}

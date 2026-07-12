package relay

import "sync"

// NavRequest is a single "the user clicked a link in the preview" event: the
// room key it happened in (the previewed document's path) and the raw href
// that was clicked (relative to that document). The relay never resolves or
// touches the filesystem — it only carries these to Neovim, which resolves the
// target against the source document and decides what to open.
type NavRequest struct {
	Key  string `json:"key"`
	Href string `json:"href"`
}

// NavQueue is a tiny thread-safe FIFO of pending navigation requests. The
// browser client enqueues on click (POST /nav); Neovim drains it by polling
// (GET /nav) while a click-navigate session is active. Bounded so a client that
// spams clicks while Neovim isn't polling can't grow it without limit.
type NavQueue struct {
	mu    sync.Mutex
	items []NavRequest
}

const maxNavQueue = 256

func NewNavQueue() *NavQueue {
	return &NavQueue{}
}

// Push appends a request, dropping the oldest if the queue is at capacity.
func (q *NavQueue) Push(r NavRequest) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.items) >= maxNavQueue {
		q.items = q.items[1:]
	}
	q.items = append(q.items, r)
}

// Drain returns all pending requests and empties the queue.
func (q *NavQueue) Drain() []NavRequest {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.items) == 0 {
		return nil
	}
	out := q.items
	q.items = nil
	return out
}

package relay

import "sync"

// EditRequest is a "the user edited a block in the preview" event: the room key
// (previewed document path), the 1-based inclusive source line range the block
// came from, the lines as they were rendered (`Expected`) and their replacement
// (`Text`). In standalone mode the relay applies it to the watched file itself;
// in Neovim-driven mode it only carries the event to Neovim, which edits the
// buffer (possibly holding unsaved changes the relay must not clobber) and
// refuses it when the lines no longer match `Expected`.
type EditRequest struct {
	Key      string `json:"key"`
	Start    int    `json:"start"`
	End      int    `json:"end"`
	Expected string `json:"expected"`
	Text     string `json:"text"`
}

// EditQueue is a tiny thread-safe FIFO of pending block edits, drained by
// Neovim's inbound poller — the same pattern as ToggleQueue/FieldQueue.
// Bounded so a client editing while Neovim isn't polling can't grow it without
// limit.
type EditQueue struct {
	mu    sync.Mutex
	items []EditRequest
}

const maxEditQueue = 64

func NewEditQueue() *EditQueue {
	return &EditQueue{}
}

// Push appends a request, dropping the oldest if the queue is at capacity.
func (q *EditQueue) Push(r EditRequest) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.items) >= maxEditQueue {
		q.items = q.items[1:]
	}
	q.items = append(q.items, r)
}

// Drain returns all pending requests and empties the queue.
func (q *EditQueue) Drain() []EditRequest {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.items) == 0 {
		return nil
	}
	out := q.items
	q.items = nil
	return out
}

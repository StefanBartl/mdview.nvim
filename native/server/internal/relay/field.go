package relay

import "sync"

// FieldRequest is a "the user edited a syncable text field in the preview"
// event: the room key (previewed document path), the field's `name`, and its
// new value. Value is arbitrary user text (may contain newlines), so unlike a
// checkbox toggle it's carried as-is rather than encoded into a compact string.
type FieldRequest struct {
	Key   string `json:"key"`
	Name  string `json:"name"`
	Value string `json:"value"`
}

// FieldQueue is a tiny thread-safe FIFO of pending field edits, drained by
// Neovim's inbound poller — same pattern as NavQueue/ToggleQueue. Bounded so a
// client editing rapidly while Neovim isn't polling can't grow it without limit.
type FieldQueue struct {
	mu    sync.Mutex
	items []FieldRequest
}

const maxFieldQueue = 256

func NewFieldQueue() *FieldQueue {
	return &FieldQueue{}
}

// Push appends a request, dropping the oldest if the queue is at capacity.
func (q *FieldQueue) Push(r FieldRequest) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.items) >= maxFieldQueue {
		q.items = q.items[1:]
	}
	q.items = append(q.items, r)
}

// Drain returns all pending requests and empties the queue.
func (q *FieldQueue) Drain() []FieldRequest {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.items) == 0 {
		return nil
	}
	out := q.items
	q.items = nil
	return out
}

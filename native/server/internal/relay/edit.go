package relay

import "sync"

// EditRequest is a "the user edited a block in the preview" event: the room key
// of the tab, the document it was showing (`Doc`; in "reuse" behavior the tab
// follows the active buffer, so its room is not that document), the 1-based
// inclusive source line range the block
// came from, the lines as they were rendered (`Expected`) and their replacement
// (`Text`). In standalone mode the relay applies it to the watched file itself;
// in Neovim-driven mode it only carries the event to Neovim, which edits the
// buffer (possibly holding unsaved changes the relay must not clobber) and
// refuses it when the lines no longer match `Expected`.
type EditRequest struct {
	Key      string `json:"key"`
	Doc      string `json:"doc,omitempty"`
	Start    int    `json:"start"`
	End      int    `json:"end"`
	Expected string `json:"expected"`
	Text     string `json:"text"`
}

// size is what the request holds in memory, for the queue's byte budget.
func (r EditRequest) size() int {
	return len(r.Key) + len(r.Doc) + len(r.Expected) + len(r.Text)
}

// EditQueue is a tiny thread-safe FIFO of pending block edits, drained by
// Neovim's inbound poller — the same pattern as ToggleQueue/FieldQueue.
// Bounded in count and in bytes (an edit can carry a whole code block), so a
// client editing while Neovim isn't polling can't grow it without limit.
type EditQueue struct {
	mu    sync.Mutex
	items []EditRequest
	bytes int
}

const (
	maxEditQueue      = 64
	maxEditQueueBytes = 4 << 20
)

func NewEditQueue() *EditQueue {
	return &EditQueue{}
}

// Push appends a request, dropping the oldest ones while the queue is at its
// count or byte capacity.
func (q *EditQueue) Push(r EditRequest) {
	q.mu.Lock()
	defer q.mu.Unlock()
	n := r.size()
	for len(q.items) > 0 && (len(q.items) >= maxEditQueue || q.bytes+n > maxEditQueueBytes) {
		q.bytes -= q.items[0].size()
		q.items = q.items[1:]
	}
	q.items = append(q.items, r)
	q.bytes += n
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
	q.bytes = 0
	return out
}

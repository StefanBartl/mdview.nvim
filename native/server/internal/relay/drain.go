package relay

// splitBy partitions items into those keep accepts (taken) and the rest, in
// their original order. Shared by the queues' DrainFor: on a shared relay each
// Neovim instance drains only the write-backs of the rooms it owns, and the
// others stay queued for their owners.
func splitBy[T any](items []T, keep func(T) bool) (taken, rest []T) {
	for _, it := range items {
		if keep(it) {
			taken = append(taken, it)
		} else {
			rest = append(rest, it)
		}
	}
	return taken, rest
}

// DrainFor returns and removes the pending requests whose room mine accepts;
// a nil mine drains everything (Drain).
func (q *NavQueue) DrainFor(mine func(key string) bool) []NavRequest {
	if mine == nil {
		return q.Drain()
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	taken, rest := splitBy(q.items, func(r NavRequest) bool { return mine(r.Key) })
	q.items = rest
	return taken
}

// DrainFor: see NavQueue.DrainFor.
func (q *ToggleQueue) DrainFor(mine func(key string) bool) []ToggleRequest {
	if mine == nil {
		return q.Drain()
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	taken, rest := splitBy(q.items, func(r ToggleRequest) bool { return mine(r.Key) })
	q.items = rest
	return taken
}

// DrainFor: see NavQueue.DrainFor.
func (q *FieldQueue) DrainFor(mine func(key string) bool) []FieldRequest {
	if mine == nil {
		return q.Drain()
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	taken, rest := splitBy(q.items, func(r FieldRequest) bool { return mine(r.Key) })
	q.items = rest
	return taken
}

// DrainFor: see NavQueue.DrainFor. Keeps the byte budget in step with what
// stays queued.
func (q *EditQueue) DrainFor(mine func(key string) bool) []EditRequest {
	if mine == nil {
		return q.Drain()
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	taken, rest := splitBy(q.items, func(r EditRequest) bool { return mine(r.Key) })
	q.items = rest
	q.bytes = 0
	for _, r := range rest {
		q.bytes += r.size()
	}
	return taken
}

// TakeFor returns and clears the pending hint when mine accepts its room, and
// leaves it for its owner otherwise; a nil mine is Take.
func (b *ScrollBox) TakeFor(mine func(key string) bool) *ScrollHint {
	if mine == nil {
		return b.Take()
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	h := b.hint
	if h == nil || !mine(h.Key) {
		return nil
	}
	b.hint = nil
	return h
}

// TabRooms returns the rooms that have at least one connection (a tab), in no
// particular order.
func (r *Registry) TabRooms() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	var out []string
	for key, members := range r.rooms {
		if len(members) > 0 {
			out = append(out, key)
		}
	}
	return out
}

// tests/client/history.test.ts
// @vitest-environment jsdom
import { describe, it, expect, vi } from 'vitest';
import { installHistory, onDocChange } from '../../src/client/render/history';

describe('browser history for the preview', () => {
  it('pushes an entry per new document and Back asks Neovim to reopen', () => {
    const navigateTo = vi.fn();
    installHistory({ navigateTo });

    onDocChange('/proj/a.md'); // first document -> replaceState (base entry)
    onDocChange('/proj/b.md'); // navigated to a new doc -> pushState
    expect((history.state as { mdviewDoc?: string }).mdviewDoc).toBe('/proj/b.md');

    // Back: browser fires popstate with the previous entry's state.
    window.dispatchEvent(new PopStateEvent('popstate', { state: { mdviewDoc: '/proj/a.md' } }));
    expect(navigateTo).toHaveBeenCalledWith('/proj/a.md');

    // Neovim reopens a.md -> doc ping. This must NOT push a new entry (it was a
    // Back navigation), or Back/Forward would loop.
    const lenBefore = history.length;
    onDocChange('/proj/a.md');
    expect(history.length).toBe(lenBefore);
  });

  it('ignores popstate without an mdviewDoc state (e.g. in-page anchors)', () => {
    const navigateTo = vi.fn();
    installHistory({ navigateTo });
    onDocChange('/proj/a.md');
    window.dispatchEvent(new PopStateEvent('popstate', { state: null }));
    expect(navigateTo).not.toHaveBeenCalled();
  });

  it('ignores a repeated doc ping for the current document', () => {
    const navigateTo = vi.fn();
    installHistory({ navigateTo });
    onDocChange('/proj/a.md');
    const len = history.length;
    onDocChange('/proj/a.md'); // same doc -> no-op
    expect(history.length).toBe(len);
  });
});

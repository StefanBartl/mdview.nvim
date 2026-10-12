// @vitest-environment jsdom
import { afterEach, beforeEach, describe, it, expect, vi } from 'vitest';
import { showToast } from '../../src/client/render/toast';

describe('showToast', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.runAllTimers();
    vi.useRealTimers();
    document.body.innerHTML = '';
  });

  it('is one persistent live region whose text is replaced', () => {
    showToast('first');
    showToast('second');
    const all = document.querySelectorAll('.mdview-toast');
    expect(all).toHaveLength(1);
    expect(all[0].textContent).toBe('second');
    expect(all[0].getAttribute('role')).toBe('status');
    expect(all[0].classList.contains('mdview-toast-on')).toBe(true);
  });

  it('shows text, never markup, and caps its length', () => {
    showToast('<img src=x onerror=alert(1)>' + 'x'.repeat(500));
    const el = document.querySelector('.mdview-toast')!;
    expect(el.querySelector('img')).toBeNull();
    expect(el.textContent!.length).toBeLessThanOrEqual(200);
  });

  it('empties and hides itself after a few seconds', () => {
    showToast('gone soon');
    vi.advanceTimersByTime(4100);
    const el = document.querySelector('.mdview-toast')!;
    expect(el.textContent).toBe('');
    expect(el.classList.contains('mdview-toast-on')).toBe(false);
  });
});

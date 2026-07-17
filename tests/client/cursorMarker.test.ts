// tests/client/cursorMarker.test.ts
// @vitest-environment jsdom
import { describe, it, expect } from 'vitest';
import { updateCursorMarker, parseCursorMarkerMode } from '../../src/client/render/cursorMarker';

// jsdom has no layout (getBoundingClientRect is 0), so this covers the mode
// parsing and the element lifecycle, not pixel positions.
describe('parseCursorMarkerMode', () => {
  it('defaults to line', () => {
    expect(parseCursorMarkerMode(null)).toBe('line');
    expect(parseCursorMarkerMode('line')).toBe('line');
    expect(parseCursorMarkerMode('off')).toBe('off');
    expect(parseCursorMarkerMode('garbage')).toBe('line');
  });
});

describe('updateCursorMarker', () => {
  function container(): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = '<h1 data-sourcepos="1:1-1:5">One</h1><p data-sourcepos="3:1-3:5">two</p>';
    document.body.appendChild(el);
    return el;
  }

  it('creates a marker element for a locatable line in "line" mode', () => {
    const el = container();
    updateCursorMarker(el, 3, 'line');
    const bar = el.querySelector('.mdview-cursor-bar') as HTMLElement;
    expect(bar).not.toBeNull();
    expect(bar.style.display).toBe('block');
  });

  it('hides the marker in "off" mode', () => {
    const el = container();
    updateCursorMarker(el, 3, 'line');
    updateCursorMarker(el, 3, 'off');
    const bar = el.querySelector('.mdview-cursor-bar') as HTMLElement;
    expect(bar.style.display).toBe('none');
  });

  it('hides the marker when the line cannot be located', () => {
    const el = container();
    updateCursorMarker(el, 3, 'line');
    updateCursorMarker(el, 0, 'line'); // before the first block
    const bar = el.querySelector('.mdview-cursor-bar') as HTMLElement;
    expect(bar.style.display).toBe('none');
  });
});

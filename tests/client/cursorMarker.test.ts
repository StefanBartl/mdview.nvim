// tests/client/cursorMarker.test.ts
// @vitest-environment jsdom
import { describe, it, expect } from 'vitest';
import { updateCursorMarker, parseCursorMarkerMode } from '../../src/client/render/cursorMarker';

// jsdom has no layout (getBoundingClientRect is 0), so this covers the mode
// parsing and the element lifecycle, not pixel positions.
describe('parseCursorMarkerMode', () => {
  it('defaults to line, and recognizes caret/off', () => {
    expect(parseCursorMarkerMode(null)).toBe('line');
    expect(parseCursorMarkerMode('line')).toBe('line');
    expect(parseCursorMarkerMode('caret')).toBe('caret');
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
    updateCursorMarker(el, 3, null, 'line');
    const bar = el.querySelector('.mdview-cursor-bar') as HTMLElement;
    expect(bar).not.toBeNull();
    expect(bar.style.display).toBe('block');
  });

  it('hides the marker in "off" mode', () => {
    const el = container();
    updateCursorMarker(el, 3, null, 'line');
    updateCursorMarker(el, 3, 0, 'off');
    const bar = el.querySelector('.mdview-cursor-bar') as HTMLElement;
    expect(bar.style.display).toBe('none');
  });

  it('hides the marker when the line cannot be located', () => {
    const el = container();
    updateCursorMarker(el, 3, null, 'line');
    updateCursorMarker(el, 0, null, 'line'); // before the first block
    const bar = el.querySelector('.mdview-cursor-bar') as HTMLElement;
    expect(bar.style.display).toBe('none');
  });

  it('places a caret element when a source-position run covers the column', () => {
    // jsdom has no layout and no Range.getBoundingClientRect; stub it so the
    // caret placement path can run (pixel correctness is verified in a real
    // browser, not here).
    const proto = Range.prototype as unknown as { getBoundingClientRect?: () => DOMRect };
    const orig = proto.getBoundingClientRect;
    proto.getBoundingClientRect = () =>
      ({ left: 10, top: 5, right: 18, bottom: 21, width: 8, height: 16 }) as DOMRect;
    try {
      const el = document.createElement('div');
      // A paragraph with an inline run tagged with its byte columns (as the WASM
      // renderer emits for cursor_marker = "caret").
      el.innerHTML = '<p data-sourcepos="1:1-1:11"><span data-sp="1:1:1:11">hello world</span></p>';
      document.body.appendChild(el);
      // cursor at byte column 6 (0-based) -> before "world"
      updateCursorMarker(el, 1, 6, 'caret');
      const caret = el.querySelector('.mdview-cursor-caret') as HTMLElement;
      expect(caret).not.toBeNull();
      expect(caret.style.display).toBe('block');
    } finally {
      if (orig) proto.getBoundingClientRect = orig;
      else delete proto.getBoundingClientRect;
    }
  });

  it('falls back to the line bar when no run covers the line (e.g. code block)', () => {
    const el = document.createElement('div');
    el.innerHTML = '<pre data-sourcepos="2:1-2:9"><code>let x = 1</code></pre>';
    document.body.appendChild(el);
    updateCursorMarker(el, 2, 4, 'caret'); // no data-sp run on this line
    const caret = el.querySelector('.mdview-cursor-caret') as HTMLElement | null;
    const bar = el.querySelector('.mdview-cursor-bar') as HTMLElement;
    expect(bar).not.toBeNull();
    expect(bar.style.display).toBe('block');
    // the caret, if it was ever created, must be hidden
    if (caret) expect(caret.style.display).toBe('none');
  });
});

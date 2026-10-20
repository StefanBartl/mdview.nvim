// TESTS/client/cursorBlock.test.ts
// @vitest-environment jsdom
//
// browser.cursor_marker = "block": a box over the character under the cursor, with
// the character's own width, and optional blinking that reduced motion switches off.
// jsdom has no layout, so Range.getBoundingClientRect is stubbed to a width computed
// from the text of the range (pixel correctness is a real-browser matter).

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  cursorModeNeedsSourceMap,
  parseCursorBlink,
  parseCursorMarkerMode,
  setCursorBlink,
  updateCursorMarker,
} from '../../src/client/render/cursorMarker';
import { parseControl } from '../../src/client/render/controlMessage';

const proto = Range.prototype as unknown as { getBoundingClientRect?: () => DOMRect };
let original: (() => DOMRect) | undefined;

/** Width of one code point in the stub layout: wide = 16, tab = 32, a lone surrogate = 5, else 8. */
function widthOf(text: string): number {
  let w = 0;
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    if (ch === '\t') w += 32;
    else if (cp >= 0xd800 && cp <= 0xdfff) w += 5;
    else if (cp >= 0x2e80) w += 16;
    else w += 8;
  }
  return w;
}

beforeEach(() => {
  original = proto.getBoundingClientRect;
  proto.getBoundingClientRect = function (this: Range) {
    const width = widthOf(this.toString());
    return { left: 10, top: 5, right: 10 + width, bottom: 21, width, height: 16 } as DOMRect;
  };
  setCursorBlink(false);
});

afterEach(() => {
  if (original) proto.getBoundingClientRect = original;
  else delete proto.getBoundingClientRect;
  setCursorBlink(false);
  delete (window as unknown as { matchMedia?: unknown }).matchMedia;
});

/** A one-paragraph document whose single inline run holds `text`. */
function doc(text: string): HTMLElement {
  const el = document.createElement('div');
  const bytes = new TextEncoder().encode(text).length;
  el.innerHTML = `<p data-sourcepos="1:1-1:${bytes}"><span data-sp="1:1:1:${bytes}"></span></p>`;
  el.querySelector('span')!.textContent = text;
  document.body.appendChild(el);
  return el;
}

function block(el: HTMLElement): HTMLElement {
  return el.querySelector('.mdview-cursor-block') as HTMLElement;
}

describe('block mode: the width of the character under the cursor', () => {
  it('is one ASCII character wide', () => {
    const el = doc('hello world');
    updateCursorMarker(el, 1, 6, 'block'); // before "world"
    expect(block(el).style.display).toBe('block');
    expect(block(el).style.width).toBe('8px');
    expect(block(el).style.left).not.toBe('');
  });

  it('is as wide as a wide character, not a fixed cell', () => {
    const el = doc('漢字x');
    updateCursorMarker(el, 1, 3, 'block'); // 漢 is 3 bytes: the cursor is on 字
    expect(block(el).style.width).toBe('16px');
  });

  it('covers a whole tab', () => {
    const el = doc('a\tb');
    updateCursorMarker(el, 1, 1, 'block');
    expect(block(el).style.width).toBe('32px');
  });

  it('keeps a surrogate pair together (one character, not half of it)', () => {
    const el = doc('😀x');
    updateCursorMarker(el, 1, 0, 'block');
    expect(block(el).style.width).toBe('16px');
  });

  it('is one character wide at the end of the line, right after the last character', () => {
    const el = doc('hello world');
    updateCursorMarker(el, 1, 11, 'block'); // past the last byte
    expect(block(el).style.width).toBe('8px');
    // box starts at the right edge of the last character (stub: left 10 + width 8)
    expect(block(el).style.left).toBe('18px');
  });

  it('hides the other markers and falls back to the line bar where no run covers the line', () => {
    const el = doc('hello');
    updateCursorMarker(el, 1, 0, 'caret');
    updateCursorMarker(el, 1, 0, 'block');
    expect((el.querySelector('.mdview-cursor-caret') as HTMLElement).style.display).toBe('none');
    updateCursorMarker(el, 1, 0, 'line');
    expect(block(el).style.display).toBe('none');

    const code = document.createElement('div');
    code.innerHTML = '<pre data-sourcepos="2:1-2:9"><code>let x = 1</code></pre>';
    document.body.appendChild(code);
    updateCursorMarker(code, 2, 4, 'block');
    expect((code.querySelector('.mdview-cursor-bar') as HTMLElement).style.display).toBe('block');
    expect(code.querySelector('.mdview-cursor-block')).toBeNull();
  });
});

describe('block mode: blinking', () => {
  it('is steady by default', () => {
    const el = doc('hello');
    updateCursorMarker(el, 1, 0, 'block');
    expect(block(el).classList.contains('mdview-cursor-blink')).toBe(false);
  });

  it('blinks with the configured period when asked to', () => {
    const el = doc('hello');
    setCursorBlink(parseCursorBlink(250));
    updateCursorMarker(el, 1, 0, 'block');
    expect(block(el).classList.contains('mdview-cursor-blink')).toBe(true);
    expect(block(el).style.getPropertyValue('--mdview-blink-ms')).toBe('250ms');
    setCursorBlink(false);
    updateCursorMarker(el, 1, 0, 'block');
    expect(block(el).classList.contains('mdview-cursor-blink')).toBe(false);
  });

  it('never blinks under prefers-reduced-motion', () => {
    (window as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
      matches: query.includes('prefers-reduced-motion'),
    });
    const el = doc('hello');
    setCursorBlink(parseCursorBlink(true));
    updateCursorMarker(el, 1, 0, 'block');
    expect(block(el).classList.contains('mdview-cursor-blink')).toBe(false);
  });

  it('has a stylesheet rule that stops the animation for reduced motion', () => {
    const css = readFileSync('src/client/themes/_base.css', 'utf8');
    expect(css).toMatch(
      /@media \(prefers-reduced-motion: reduce\)\s*\{\s*\.mdview-cursor-block\.mdview-cursor-blink\s*\{\s*animation:\s*none/,
    );
  });
});

describe('parsing', () => {
  it('knows the block mode and that it needs the source map', () => {
    expect(parseCursorMarkerMode('block')).toBe('block');
    expect(cursorModeNeedsSourceMap('block')).toBe(true);
    expect(cursorModeNeedsSourceMap('caret')).toBe(true);
    expect(cursorModeNeedsSourceMap('line')).toBe(false);
    expect(cursorModeNeedsSourceMap('section')).toBe(false);
  });

  it('reads the blink setting from the URL and from a control message', () => {
    expect(parseCursorBlink(null)).toBe(false);
    expect(parseCursorBlink('0')).toBe(false);
    expect(parseCursorBlink('')).toBe(false);
    expect(parseCursorBlink('1')).toBe(530);
    expect(parseCursorBlink(true)).toBe(530);
    expect(parseCursorBlink(false)).toBe(false);
    expect(parseCursorBlink('300')).toBe(300);
    expect(parseCursorBlink(10)).toBe(100); // clamped
    expect(parseCursorBlink(999999)).toBe(5000);
    expect(parseCursorBlink('nonsense')).toBe(false);
  });

  it('carries cursorBlink through the control message', () => {
    expect(parseControl('{"cursor":"block","cursorBlink":420}')).toMatchObject({
      cursor: 'block',
      cursorBlink: 420,
    });
    expect(parseControl('{"cursorBlink":false}')?.cursorBlink).toBe(false);
    expect(parseControl('{"cursorBlink":"x"}')?.cursorBlink).toBeUndefined();
  });
});

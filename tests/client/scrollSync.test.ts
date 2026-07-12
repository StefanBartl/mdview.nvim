// tests/client/scrollSync.test.ts
// @vitest-environment jsdom
import { describe, it, expect } from 'vitest';
import { pickScrollTarget, fractionInBlock, hasSourcepos } from '../../src/client/render/scrollSync';

function container(html: string): HTMLElement {
  const el = document.createElement('div');
  el.innerHTML = html;
  return el;
}

// Mirrors real WASM output: block elements tagged with data-sourcepos.
const DOC = container(
  '<h1 data-sourcepos="1:1-1:5">One</h1>' +
    '<p data-sourcepos="3:1-6:11">a four line paragraph</p>' + // spans lines 3..6
    '<pre data-sourcepos="8:1-11:3"><code>code</code></pre>' +
    '<p data-sourcepos="13:1-13:5">last</p>',
);

describe('pickScrollTarget', () => {
  it('picks the block that contains the cursor line', () => {
    expect(pickScrollTarget(DOC, 1)?.el.textContent).toBe('One');
    expect(pickScrollTarget(DOC, 4)?.el.textContent).toBe('a four line paragraph'); // inside 3..6
    expect(pickScrollTarget(DOC, 9)?.el.tagName).toBe('PRE'); // inside 8..11
    expect(pickScrollTarget(DOC, 13)?.el.textContent).toBe('last');
  });

  it('falls back to the closest block before a blank/gap line', () => {
    // line 7 is between the paragraph (3-6) and the code (8-11) -> the paragraph
    expect(pickScrollTarget(DOC, 7)?.el.textContent).toBe('a four line paragraph');
    // line 20 is past the last block -> the last block
    expect(pickScrollTarget(DOC, 20)?.el.textContent).toBe('last');
  });

  it('returns null before the first block', () => {
    expect(pickScrollTarget(DOC, 0)).toBeNull();
  });

  it('picks the smallest-span containing block when nested', () => {
    const nested = container(
      '<ul data-sourcepos="1:1-4:0"><li data-sourcepos="2:1-2:8"><p data-sourcepos="2:3-2:8">x</p></li></ul>',
    );
    // line 2 is contained by ul(1-4), li(2-2) and p(2-2); smallest span wins (li or p, span 0)
    const t = pickScrollTarget(nested, 2);
    expect(t?.el.tagName === 'LI' || t?.el.tagName === 'P').toBe(true);
  });
});

describe('fractionInBlock', () => {
  it('interpolates the cursor line through the block span', () => {
    const t = { el: document.createElement('p'), startLine: 3, endLine: 6 };
    expect(fractionInBlock(t, 3)).toBeCloseTo(0);
    expect(fractionInBlock(t, 6)).toBeCloseTo(1);
    expect(fractionInBlock(t, 4)).toBeCloseTo(1 / 3);
  });

  it('is 0 for a single-line block and clamps out-of-range', () => {
    const single = { el: document.createElement('h1'), startLine: 5, endLine: 5 };
    expect(fractionInBlock(single, 5)).toBe(0);
    const t = { el: document.createElement('p'), startLine: 3, endLine: 6 };
    expect(fractionInBlock(t, 100)).toBe(1);
    expect(fractionInBlock(t, 1)).toBe(0);
  });
});

describe('hasSourcepos', () => {
  it('detects presence of sourcepos hints', () => {
    expect(hasSourcepos(DOC)).toBe(true);
    expect(hasSourcepos(container('<p>no hints</p>'))).toBe(false);
  });
});

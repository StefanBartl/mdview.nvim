// tests/client/scrollSync.test.ts
// @vitest-environment jsdom
import { describe, it, expect } from 'vitest';
import { pickSourceposTarget, hasSourcepos } from '../../src/client/render/scrollSync';

function container(html: string): HTMLElement {
  const el = document.createElement('div');
  el.innerHTML = html;
  return el;
}

// Mirrors real WASM output: block elements tagged with data-sourcepos.
const DOC = container(
  '<h1 data-sourcepos="1:1-1:5">One</h1>' +
    '<p data-sourcepos="3:1-3:11">second line</p>' +
    '<pre data-sourcepos="5:1-8:3"><code>code</code></pre>' +
    '<p data-sourcepos="10:1-10:5">third</p>',
);

describe('pickSourceposTarget', () => {
  it('picks the block starting exactly on the cursor line', () => {
    expect(pickSourceposTarget(DOC, 3)?.textContent).toBe('second line');
    expect(pickSourceposTarget(DOC, 10)?.textContent).toBe('third');
  });

  it('picks the nearest block at or above the cursor line', () => {
    // line 4 is between the <p> (3) and <pre> (5) -> the <p>
    expect(pickSourceposTarget(DOC, 4)?.textContent).toBe('second line');
    // line 7 is inside the code block (5-8) -> the <pre>
    expect(pickSourceposTarget(DOC, 7)?.tagName).toBe('PRE');
    // line 20 is past the last block -> the last block
    expect(pickSourceposTarget(DOC, 20)?.textContent).toBe('third');
  });

  it('returns null when the cursor is before the first block', () => {
    expect(pickSourceposTarget(DOC, 0)).toBeNull();
  });

  it('reports presence of sourcepos hints', () => {
    expect(hasSourcepos(DOC)).toBe(true);
    expect(hasSourcepos(container('<p>no hints</p>'))).toBe(false);
  });
});

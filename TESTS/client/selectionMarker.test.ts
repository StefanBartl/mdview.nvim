// TESTS/client/selectionMarker.test.ts
// @vitest-environment jsdom
import { describe, it, expect } from 'vitest';
import { parseSelection, updateSelection } from '../../src/client/render/selectionMarker';
import {
  positionAt,
  lineStartPosition,
  lineEndPosition,
  byteOffsetToUtf16,
} from '../../src/client/render/sourcePos';

// jsdom has no layout (getClientRects() is empty), so the rectangles themselves
// can't be asserted here. What can — and what the highlight is actually made of
// — is the source-position mapping: which text node and offset a Neovim
// line/byte-column pair lands on.

describe('parseSelection', () => {
  it('accepts the three shapes Neovim sends', () => {
    expect(parseSelection({ mode: 'char', sl: 1, sc: 2, el: 3, ec: 4 })).toEqual({
      mode: 'char',
      sl: 1,
      sc: 2,
      el: 3,
      ec: 4,
    });
    expect(parseSelection({ mode: 'line', sl: 1, sc: 1, el: 1, ec: 1 })?.mode).toBe('line');
    expect(parseSelection({ mode: 'block', sl: 1, sc: 1, el: 2, ec: 5 })?.mode).toBe('block');
  });

  it('treats "no selection" and anything malformed as null', () => {
    expect(parseSelection(false)).toBeNull(); // what Neovim sends on leaving visual mode
    expect(parseSelection(null)).toBeNull();
    expect(parseSelection(undefined)).toBeNull();
    expect(parseSelection({ mode: 'select', sl: 1, sc: 1, el: 1, ec: 1 })).toBeNull();
    expect(parseSelection({ mode: 'char', sl: 0, sc: 1, el: 1, ec: 1 })).toBeNull(); // lines are 1-based
    expect(parseSelection({ mode: 'char', sl: 5, sc: 1, el: 2, ec: 1 })).toBeNull(); // end before start
    expect(parseSelection({ mode: 'char', sl: 1, sc: 1, el: 'x', ec: 1 })).toBeNull();
  });
});

describe('byteOffsetToUtf16', () => {
  it('maps a byte offset inside a multi-byte character past that character', () => {
    // "ä" is 2 bytes / 1 UTF-16 unit: an inclusive end column pointing at its
    // first byte must cover the whole character.
    expect(byteOffsetToUtf16('äb', 0)).toBe(0);
    expect(byteOffsetToUtf16('äb', 1)).toBe(1);
    expect(byteOffsetToUtf16('äb', 2)).toBe(1);
    expect(byteOffsetToUtf16('äb', 3)).toBe(2);
  });
});

describe('positionAt over inline runs', () => {
  function doc(): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML =
      '<p data-sourcepos="1:1-1:11"><span data-sp="1:1:1:11">hello world</span></p>' +
      '<p data-sourcepos="3:1-3:2"><span data-sp="3:1:3:2">äb</span></p>';
    document.body.appendChild(el);
    return el;
  }

  it('resolves a start column to the offset before that character', () => {
    const el = doc();
    expect(positionAt(el, 1, 1, 'before')?.offset).toBe(0);
    expect(positionAt(el, 1, 7, 'before')?.offset).toBe(6); // the "w" of "world"
  });

  it('resolves an inclusive end column to the offset after that character', () => {
    const el = doc();
    expect(positionAt(el, 1, 5, 'after')?.offset).toBe(5); // through "hello"
    expect(positionAt(el, 3, 1, 'after')?.offset).toBe(1); // the whole 2-byte "ä"
  });

  it('clamps a column past the end of the line to the line end', () => {
    const el = doc();
    expect(positionAt(el, 1, 999, 'before')?.offset).toBe(11);
  });

  it('has no position for a line with no content', () => {
    const el = doc();
    expect(positionAt(el, 2, 1, 'before')).toBeNull();
  });

  it('finds the start and end of a line', () => {
    const el = doc();
    expect(lineStartPosition(el, 1)?.offset).toBe(0);
    expect(lineEndPosition(el, 1)?.offset).toBe(11);
  });
});

describe('positionAt inside code blocks', () => {
  // Code blocks carry no inline runs (the renderer leaves them for the client
  // highlighter), so their columns are resolved from the block's own lines.
  it('maps a line inside a fenced block, whose sourcepos spans the delimiters', () => {
    const el = document.createElement('div');
    el.innerHTML = '<pre data-sourcepos="3:1-6:3"><code>one\ntwo\n</code></pre>';
    document.body.appendChild(el);
    // Content starts on line 4: "one" is line 4, "two" is line 5.
    expect(positionAt(el, 4, 1, 'before')?.offset).toBe(0);
    expect(positionAt(el, 5, 2, 'before')?.offset).toBe(5); // the "w" of "two"
    expect(lineEndPosition(el, 5)?.offset).toBe(7);
    expect(positionAt(el, 9, 1, 'before')).toBeNull(); // past the block
  });

  it('maps an indented block, whose sourcepos spans only its content', () => {
    const el = document.createElement('div');
    el.innerHTML = '<pre data-sourcepos="3:1-4:7"><code>a\nb\n</code></pre>';
    document.body.appendChild(el);
    expect(positionAt(el, 3, 1, 'before')?.offset).toBe(0);
    expect(positionAt(el, 4, 1, 'before')?.offset).toBe(2);
  });
});

describe('updateSelection', () => {
  function doc(): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = '<p data-sourcepos="1:1-1:5"><span data-sp="1:1:1:5">hello</span></p>';
    document.body.appendChild(el);
    return el;
  }

  it('draws nothing where there is no layout, and never throws', () => {
    const el = doc();
    expect(() => updateSelection(el, { mode: 'char', sl: 1, sc: 1, el: 1, ec: 5 })).not.toThrow();
    expect(el.querySelectorAll('.mdview-selection-rect')).toHaveLength(0);
  });

  it('removes a previous highlight when cleared', () => {
    const el = doc();
    const layer = document.createElement('div');
    layer.className = 'mdview-selection-layer';
    el.appendChild(layer);
    updateSelection(el, null);
    expect(el.querySelector('.mdview-selection-layer')).toBeNull();
  });

  it('survives a selection addressing lines the document no longer has', () => {
    const el = doc();
    expect(() =>
      updateSelection(el, { mode: 'line', sl: 900, sc: 1, el: 999, ec: 1 }),
    ).not.toThrow();
  });
});

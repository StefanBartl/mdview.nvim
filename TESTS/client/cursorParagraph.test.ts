// tests/client/cursorParagraph.test.ts
// @vitest-environment jsdom
//
// Cursor paragraph highlight: which top-level block a source line maps to, for
// every block kind of the preview. The HTML below is what the WASM renderer
// emits for this document (data-sourcepos as comrak writes it):
//
//   1  ---                    frontmatter -> table 1..4
//   2  id: x
//   3  title: y
//   4  ---
//   5
//   6  # Heading
//   7
//   8  Para line one          paragraph 8..9
//   9  para line two
//  10
//  11  - item a               list 11..14 (comrak: 11:1-15:0)
//  12  - item b
//  13
//  14    continued item b
//  15
//  16  | a | b |              table 16..18
//  17  |---|---|
//  18  | 1 | 2 |
//  19
//  20  ```lua                 code block 20..24, blank line 22 inside
//  21  local a = 1
//  22
//  23  local b = 2
//  24  ```
//  25
//  26  > quote                block quote 26..27
//  27  > more

import { describe, it, expect } from 'vitest';
import {
  paragraphBlockAt,
  updateCursorParagraph,
  parseCursorParagraph,
  parseParagraphColor,
  applyParagraphColor,
  PARAGRAPH_CLASS,
  PARAGRAPH_BG_VAR,
} from '../../src/client/render/cursorParagraph';
import { topLevelBlocks } from '../../src/client/render/docModel';

const RENDERED =
  '<table data-sourcepos="1:1-4:3"><caption>Frontmatter</caption><tbody>' +
  '<tr><th>id</th><td>x</td></tr><tr><th>title</th><td>y</td></tr></tbody></table>\n' +
  '<h1 data-sourcepos="6:1-6:9">Heading</h1>\n' +
  '<p data-sourcepos="8:1-9:13">Para line one\npara line two</p>\n' +
  '<ul data-sourcepos="11:1-15:0">\n' +
  '<li data-sourcepos="11:1-11:8"><p data-sourcepos="11:3-11:8">item a</p></li>\n' +
  '<li data-sourcepos="12:1-15:0"><p data-sourcepos="12:3-12:8">item b</p>' +
  '<p data-sourcepos="14:3-14:18">continued item b</p></li>\n</ul>\n' +
  '<table data-sourcepos="16:1-18:9"><thead><tr data-sourcepos="16:1-16:9">' +
  '<th data-sourcepos="16:2-16:4">a</th><th data-sourcepos="16:6-16:8">b</th></tr></thead>' +
  '<tbody><tr data-sourcepos="18:1-18:9"><td data-sourcepos="18:2-18:4">1</td>' +
  '<td data-sourcepos="18:6-18:8">2</td></tr></tbody></table>\n' +
  '<pre data-sourcepos="20:1-24:3"><code class="language-lua">local a = 1\n\nlocal b = 2\n</code></pre>\n' +
  '<blockquote data-sourcepos="26:1-27:6"><p data-sourcepos="26:3-27:6">quote\nmore</p></blockquote>\n';

function doc(): HTMLElement {
  const el = document.createElement('div');
  el.innerHTML = RENDERED;
  document.body.appendChild(el);
  return el;
}

/** Tag name of the block line `line` maps to, or null. */
function blockTag(container: HTMLElement, line: number): string | null {
  return paragraphBlockAt(topLevelBlocks(container), line)?.el.tagName ?? null;
}

describe('paragraphBlockAt (source line -> top-level block)', () => {
  const el = doc();

  it('maps every frontmatter line, both delimiters included, to the frontmatter table', () => {
    for (const line of [1, 2, 3, 4]) {
      const b = paragraphBlockAt(topLevelBlocks(el), line);
      expect(b?.el.tagName).toBe('TABLE');
      expect(b?.el.querySelector('caption')?.textContent).toBe('Frontmatter');
    }
  });

  it('maps a heading line to the heading', () => {
    expect(blockTag(el, 6)).toBe('H1');
  });

  it('maps each line of a paragraph to the paragraph', () => {
    expect(blockTag(el, 8)).toBe('P');
    expect(blockTag(el, 9)).toBe('P');
  });

  it('treats a whole list as one block, a blank line between items included', () => {
    for (const line of [11, 12, 13, 14]) expect(blockTag(el, line)).toBe('UL');
  });

  it('does not count the blank line comrak lets a list end on', () => {
    expect(blockTag(el, 15)).toBeNull();
  });

  it('treats a whole table as one block, the delimiter row included', () => {
    for (const line of [16, 17, 18]) expect(blockTag(el, line)).toBe('TABLE');
    expect(paragraphBlockAt(topLevelBlocks(el), 17)?.el.querySelector('caption')).toBeNull();
  });

  it('keeps a code block with a blank line inside together, fences included', () => {
    for (const line of [20, 21, 22, 23, 24]) expect(blockTag(el, line)).toBe('PRE');
  });

  it('maps a block quote to the quote, not to its inner paragraph', () => {
    expect(blockTag(el, 26)).toBe('BLOCKQUOTE');
    expect(blockTag(el, 27)).toBe('BLOCKQUOTE');
  });

  it('maps blank lines between blocks and lines past the end to nothing', () => {
    for (const line of [5, 7, 10, 19, 25, 28, 100]) expect(blockTag(el, line)).toBeNull();
  });
});

describe('updateCursorParagraph', () => {
  it('marks the block under the cursor and moves with it', () => {
    const el = doc();
    updateCursorParagraph(el, 9, true);
    const marked = () => Array.from(el.querySelectorAll(`.${PARAGRAPH_CLASS}`));
    expect(marked().map(e => e.tagName)).toEqual(['P']);

    updateCursorParagraph(el, 22, true);
    expect(marked().map(e => e.tagName)).toEqual(['PRE']);
  });

  it('clears the mark on a blank line, when switched off, and for no cursor yet', () => {
    const el = doc();
    updateCursorParagraph(el, 8, true);
    updateCursorParagraph(el, 10, true);
    expect(el.querySelector(`.${PARAGRAPH_CLASS}`)).toBeNull();

    updateCursorParagraph(el, 8, true);
    updateCursorParagraph(el, 8, false);
    expect(el.querySelector(`.${PARAGRAPH_CLASS}`)).toBeNull();

    updateCursorParagraph(el, -1, true);
    expect(el.querySelector(`.${PARAGRAPH_CLASS}`)).toBeNull();
  });

  it('marks only the top-level block, never a nested one', () => {
    const el = doc();
    updateCursorParagraph(el, 26, true);
    expect(el.querySelector('blockquote')?.classList.contains(PARAGRAPH_CLASS)).toBe(true);
    expect(el.querySelector('blockquote p')?.classList.contains(PARAGRAPH_CLASS)).toBe(false);
  });
});

describe('switch and color parsing', () => {
  it('is on only for ?para=1', () => {
    expect(parseCursorParagraph('1')).toBe(true);
    expect(parseCursorParagraph('0')).toBe(false);
    expect(parseCursorParagraph(null)).toBe(false);
  });

  it('accepts #rrggbb with or without the hash, nothing else', () => {
    expect(parseParagraphColor('2A3B4C')).toBe('#2a3b4c');
    expect(parseParagraphColor('#2a3b4c')).toBe('#2a3b4c');
    expect(parseParagraphColor('red')).toBeNull();
    expect(parseParagraphColor('#123')).toBeNull();
    expect(parseParagraphColor('1;x:url(y)')).toBeNull();
    expect(parseParagraphColor(false)).toBeNull();
  });

  it('sets and drops the color variable', () => {
    const el = document.createElement('div');
    applyParagraphColor(el, '#112233');
    expect(el.style.getPropertyValue(PARAGRAPH_BG_VAR)).toBe('#112233');
    applyParagraphColor(el, null);
    expect(el.style.getPropertyValue(PARAGRAPH_BG_VAR)).toBe('');
  });
});

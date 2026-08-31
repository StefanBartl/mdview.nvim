// TESTS/client/nvimHighlight.test.ts
// @vitest-environment jsdom
import { describe, it, expect, beforeEach } from 'vitest';
import { setSpans, hasSpans, highlightAll } from '../../src/client/highlight/nvim';
import { parseHighlighter } from '../../src/client/highlight';

// The nvim highlighter paints code blocks from colors Neovim sends rather than
// tokenizing anything itself, so what needs guarding is the mapping: which
// block a payload addresses, which bytes a span covers, and — most of all —
// that a block Neovim did not paint is handed to highlight.js instead of being
// rendered flat. color_my_ascii covers 31 fence tags; meeting an unpainted
// block is the normal case, not the edge case.

function doc(html: string): HTMLElement {
  const root = document.createElement('div');
  root.innerHTML = html;
  document.body.appendChild(root);
  return root;
}

/** A fenced block: sourcepos spans the delimiters, so content starts at s+1. */
function fenced(start: number, end: number, lang: string, code: string): string {
  return `<pre data-sourcepos="${start}:1-${end}:3"><code class="language-${lang}">${code}\n</code></pre>`;
}

beforeEach(() => {
  document.body.innerHTML = '';
  setSpans(null);
});

describe('parseHighlighter', () => {
  it('recognizes nvim alongside the others', () => {
    expect(parseHighlighter('nvim')).toBe('nvim');
    expect(parseHighlighter('hljs')).toBe('hljs');
    expect(parseHighlighter('garbage')).toBe('hljs');
  });
});

describe('setSpans', () => {
  it('accepts a well-formed payload', () => {
    setSpans({ v: 1, blocks: [{ line: 6, rows: [[{ c: 1, n: 5, f: '#af87af' }]] }] });
    expect(hasSpans()).toBe(true);
  });

  it('rejects an unknown version rather than guessing at the shape', () => {
    setSpans({ v: 99, blocks: [{ line: 6, rows: [[]] }] });
    expect(hasSpans()).toBe(false);
  });

  it('treats null, junk and empty block lists as "nothing to paint"', () => {
    setSpans(null);
    expect(hasSpans()).toBe(false);
    setSpans('not an object');
    expect(hasSpans()).toBe(false);
    setSpans({ v: 1, blocks: [] });
    expect(hasSpans()).toBe(false);
  });
});

describe('highlightAll', () => {
  it('paints the block the payload addresses, by its first content line', async () => {
    const root = doc(fenced(5, 7, 'lua', 'local M = {}'));
    setSpans({
      v: 1,
      blocks: [
        {
          line: 6, // first content line of a block whose fence opens on line 5
          rows: [
            [
              { c: 1, n: 5, f: '#af87af', b: true }, // "local"
              { c: 7, n: 1, f: '#d75f87' }, // "M"
            ],
          ],
        },
      ],
    });
    await highlightAll(root);

    const code = root.querySelector('code')!;
    expect(code.hasAttribute('data-nvim-hl')).toBe(true);
    expect(code.textContent).toBe('local M = {}\n');
    const spans = [...code.querySelectorAll('span[style]')];
    expect(spans.map(s => s.textContent)).toEqual(['local', 'M']);
    expect(spans[0].getAttribute('style')).toBe('color:#af87af;font-weight:bold');
    expect(spans[1].getAttribute('style')).toBe('color:#d75f87');
  });

  it('hands a block with no spans to highlight.js instead of leaving it flat', async () => {
    const root = doc(fenced(5, 7, 'javascript', 'const x = 1;'));
    setSpans({ v: 1, blocks: [{ line: 99, rows: [[]] }] }); // addresses another block
    await highlightAll(root);

    const code = root.querySelector('code')!;
    expect(code.hasAttribute('data-nvim-hl')).toBe(false);
    expect(code.classList.contains('hljs')).toBe(true);
    expect(code.querySelector('.hljs-keyword')).not.toBeNull();
  });

  it('paints one block and lets highlight.js take the other, in one document', async () => {
    const root = doc(fenced(5, 7, 'lua', 'local M = {}') + fenced(9, 11, 'javascript', 'const x = 1;'));
    setSpans({ v: 1, blocks: [{ line: 6, rows: [[{ c: 1, n: 5, f: '#af87af' }]] }] });
    await highlightAll(root);

    const [lua, js] = [...root.querySelectorAll('code')];
    expect(lua.hasAttribute('data-nvim-hl')).toBe(true);
    expect(lua.classList.contains('hljs')).toBe(false);
    expect(js.hasAttribute('data-nvim-hl')).toBe(false);
    expect(js.classList.contains('hljs')).toBe(true);
  });

  it('addresses multi-byte characters by byte column, not by character', async () => {
    // "-- ä" : the ä starts at byte column 4 and is 2 bytes long.
    const root = doc(fenced(5, 7, 'lua', '-- ä!'));
    setSpans({ v: 1, blocks: [{ line: 6, rows: [[{ c: 4, n: 2, f: '#5f8787' }]] }] });
    await highlightAll(root);

    const span = root.querySelector('code span[style]')!;
    expect(span.textContent).toBe('ä');
    expect(root.querySelector('code')!.textContent).toBe('-- ä!\n');
  });

  it('leaves a block alone when the payload has a different number of rows', async () => {
    // An edit landed between the content push and the spans push: painting
    // would put the colors on the wrong lines.
    const root = doc(fenced(5, 8, 'lua', 'local M = {}\nreturn M'));
    setSpans({ v: 1, blocks: [{ line: 6, rows: [[{ c: 1, n: 5, f: '#af87af' }]] }] });
    await highlightAll(root);

    expect(root.querySelector('code')!.hasAttribute('data-nvim-hl')).toBe(false);
  });

  it('never lets code text become markup', async () => {
    const root = doc(fenced(5, 7, 'html', '&lt;img src=x onerror=alert(1)&gt;'));
    setSpans({ v: 1, blocks: [{ line: 6, rows: [[{ c: 1, n: 4, f: '#af87af' }]] }] });
    await highlightAll(root);

    const code = root.querySelector('code')!;
    expect(code.querySelector('img')).toBeNull();
    expect(code.textContent).toBe('<img src=x onerror=alert(1)>\n');
  });
});

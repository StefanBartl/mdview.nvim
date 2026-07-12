// tests/client/highlight.test.ts
// @vitest-environment jsdom
import { describe, it, expect } from 'vitest';
import { parseHighlighter } from '../../src/client/highlight';
import { highlightAll } from '../../src/client/highlight/hljs';

describe('parseHighlighter', () => {
  it('defaults to hljs and recognizes shiki/none', () => {
    expect(parseHighlighter(null)).toBe('hljs');
    expect(parseHighlighter(undefined)).toBe('hljs');
    expect(parseHighlighter('hljs')).toBe('hljs');
    expect(parseHighlighter('shiki')).toBe('shiki');
    expect(parseHighlighter('none')).toBe('none');
    expect(parseHighlighter('garbage')).toBe('hljs');
  });
});

describe('highlight.js highlightAll', () => {
  it('adds hljs token classes to a fenced code block', () => {
    const root = document.createElement('div');
    root.innerHTML = '<pre><code class="language-javascript">const x = 1;</code></pre>';
    highlightAll(root);
    const code = root.querySelector('code')!;
    expect(code.classList.contains('hljs')).toBe(true);
    // "const" is a keyword -> a .hljs-keyword span is produced
    expect(code.querySelector('.hljs-keyword')).not.toBeNull();
  });

  it('does not throw on a block with no language class', () => {
    const root = document.createElement('div');
    root.innerHTML = '<pre><code>plain text</code></pre>';
    expect(() => highlightAll(root)).not.toThrow();
  });
});

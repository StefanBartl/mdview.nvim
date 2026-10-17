// @vitest-environment jsdom
//
// Shiki replaces a fenced block with its themed copy, keeps the block's
// data-sourcepos and the cursor paragraph tint, and leaves a block alone that
// the block editor has hidden.

import { describe, it, expect, vi } from 'vitest';

const hooks = vi.hoisted(() => ({ onLoad: undefined as (() => void) | undefined }));

vi.mock('shiki/engine/javascript', () => ({ createJavaScriptRegexEngine: () => ({}) }));
vi.mock('shiki', () => {
  const hl = {
    getLoadedThemes: () => ['github-dark'],
    getLoadedLanguages: () => ['js'],
    loadTheme: async () => undefined,
    // Awaited for a language that is not loaded yet: the point at which an editor
    // can open on the block while the highlighter is busy.
    loadLanguage: async () => {
      await Promise.resolve();
      hooks.onLoad?.();
    },
    codeToHtml: (code: string) => `<pre class="shiki"><code>HL:${code}</code></pre>`,
  };
  return {
    createHighlighter: async () => hl,
    bundledLanguages: { js: {}, py: {} },
    bundledThemes: { 'github-dark': {} },
  };
});

import { highlightAll } from '../../src/client/highlight/shiki';

function setup(html: string) {
  const root = document.createElement('div');
  root.innerHTML = html;
  document.body.appendChild(root);
  return root;
}

describe('highlightAll (shiki)', () => {
  it('replaces a block and keeps its data-sourcepos', async () => {
    const root = setup('<pre data-sourcepos="3:1-5:3"><code class="language-js">a()</code></pre>');
    await highlightAll(root);
    const pre = root.querySelector('pre')!;
    expect(pre.classList.contains('shiki')).toBe(true);
    expect(pre.textContent).toBe('HL:a()');
    expect(pre.getAttribute('data-sourcepos')).toBe('3:1-5:3');
  });

  it('keeps the cursor paragraph tint on the replaced block', async () => {
    // The render tints the old <pre> synchronously; no cursor ping follows the
    // async swap, so the class has to move over with it.
    const root = setup(
      '<pre data-sourcepos="1:1-3:3" class="mdview-cursor-paragraph"><code class="language-js">a()</code></pre>' +
        '<pre data-sourcepos="5:1-7:3"><code class="language-js">b()</code></pre>',
    );
    await highlightAll(root);
    const pres = root.querySelectorAll('pre');
    expect(pres[0].classList.contains('shiki')).toBe(true);
    expect(pres[0].classList.contains('mdview-cursor-paragraph')).toBe(true);
    expect(pres[1].classList.contains('mdview-cursor-paragraph')).toBe(false);
  });

  it('skips a block the editor has hidden', async () => {
    const root = setup(
      '<pre data-sourcepos="1:1-3:3" style="display: none"><code class="language-js">a()</code></pre>' +
        '<pre data-sourcepos="5:1-7:3"><code class="language-js">b()</code></pre>',
    );
    await highlightAll(root);
    const pres = root.querySelectorAll('pre');
    expect(pres).toHaveLength(2);
    expect(pres[0].classList.contains('shiki')).toBe(false);
    expect(pres[0].textContent).toBe('a()');
    expect(pres[1].classList.contains('shiki')).toBe(true);
  });

  it('leaves a block alone that the editor hides while its language loads', async () => {
    const root = setup('<pre data-sourcepos="1:1-3:3"><code class="language-py">a()</code></pre>');
    const pre = root.querySelector('pre')!;
    hooks.onLoad = () => {
      pre.style.display = 'none';
    };
    try {
      await highlightAll(root);
    } finally {
      hooks.onLoad = undefined;
    }
    const pres = root.querySelectorAll('pre');
    expect(pres).toHaveLength(1);
    expect(pres[0].classList.contains('shiki')).toBe(false);
    expect(pres[0].textContent).toBe('a()');
  });
});

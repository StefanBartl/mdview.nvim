// tests/client/plainText.test.ts
// @vitest-environment jsdom
import { describe, it, expect } from 'vitest';
import { renderPlainText } from '../../src/client/render/plainText';

describe('renderPlainText', () => {
  it('renders the text inside a <pre><code class="language-x"> with the right language', () => {
    const container = document.createElement('div');
    renderPlainText(container, 'local x = 1', 'init.lua');
    const code = container.querySelector('pre > code')!;
    expect(code.className).toBe('language-lua');
    expect(code.textContent).toBe('local x = 1');
  });

  it('uses "plaintext" for an unknown extension', () => {
    const container = document.createElement('div');
    renderPlainText(container, 'hello', 'notes.txt');
    const code = container.querySelector('pre > code')!;
    expect(code.className).toBe('language-plaintext');
  });

  it('treats file content as inert text, never as markup', () => {
    const container = document.createElement('div');
    renderPlainText(container, '<script>alert(1)</script>', 'notes.txt');
    expect(container.querySelector('script')).toBeNull();
    expect(container.querySelector('code')!.textContent).toBe('<script>alert(1)</script>');
  });

  it('replaces previous content on re-render', () => {
    const container = document.createElement('div');
    renderPlainText(container, 'first', 'a.txt');
    renderPlainText(container, 'second', 'a.txt');
    expect(container.querySelectorAll('pre').length).toBe(1);
    expect(container.querySelector('code')!.textContent).toBe('second');
  });
});

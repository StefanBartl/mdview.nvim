// tests/client/externalLinks.test.ts
// @vitest-environment jsdom
import { describe, it, expect } from 'vitest';
import {
  isExternalHref,
  markExternalLinks,
  parseExternalLinkMode,
} from '../../src/client/render/externalLinks';

describe('isExternalHref', () => {
  it('treats scheme/protocol-relative/absolute as external', () => {
    expect(isExternalHref('https://example.com')).toBe(true);
    expect(isExternalHref('mailto:a@b.com')).toBe(true);
    expect(isExternalHref('//cdn.example.com/x')).toBe(true);
    expect(isExternalHref('/root/abs')).toBe(true);
  });
  it('treats relative docs and in-page anchors as internal', () => {
    expect(isExternalHref('other.md')).toBe(false);
    expect(isExternalHref('./sub/x.md')).toBe(false);
    expect(isExternalHref('#heading')).toBe(false);
    expect(isExternalHref('')).toBe(false);
    expect(isExternalHref(null)).toBe(false);
  });
});

describe('markExternalLinks', () => {
  function root(html: string): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = html;
    return el;
  }

  it('opens external links in a new tab, leaves relative/anchor alone', () => {
    const el = root(
      '<a href="https://example.com" id="ext">e</a>' +
        '<a href="other.md" id="rel">r</a>' +
        '<a href="#h" id="anch">a</a>',
    );
    markExternalLinks(el, 'new_tab');
    expect(el.querySelector('#ext')!.getAttribute('target')).toBe('_blank');
    expect(el.querySelector('#ext')!.getAttribute('rel')).toBe('noopener noreferrer');
    expect(el.querySelector('#rel')!.getAttribute('target')).toBeNull();
    expect(el.querySelector('#anch')!.getAttribute('target')).toBeNull();
  });

  it('same_tab mode leaves everything alone', () => {
    const el = root('<a href="https://example.com" id="ext">e</a>');
    markExternalLinks(el, 'same_tab');
    expect(el.querySelector('#ext')!.getAttribute('target')).toBeNull();
  });

  it('parses the mode with new_tab default', () => {
    expect(parseExternalLinkMode(null)).toBe('new_tab');
    expect(parseExternalLinkMode('new_tab')).toBe('new_tab');
    expect(parseExternalLinkMode('same_tab')).toBe('same_tab');
    expect(parseExternalLinkMode('garbage')).toBe('new_tab');
  });
});

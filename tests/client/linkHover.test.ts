// tests/client/linkHover.test.ts
// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from 'vitest';
import { classifyHref, describeUrl, slugify, installLinkHover } from '../../src/client/render/linkHover';

describe('classifyHref', () => {
  it('classifies in-page anchors', () => {
    expect(classifyHref('#heading')).toBe('anchor');
    expect(classifyHref('#')).toBe('anchor');
  });

  it('classifies external targets as urls', () => {
    expect(classifyHref('https://example.com')).toBe('url');
    expect(classifyHref('mailto:a@b.com')).toBe('url');
    expect(classifyHref('//cdn.example.com/x')).toBe('url');
    expect(classifyHref('/root/abs.md')).toBe('url');
  });

  it('classifies relative targets by extension', () => {
    expect(classifyHref('photo.png')).toBe('image');
    expect(classifyHref('./assets/pic.JPG')).toBe('image');
    expect(classifyHref('notes.md')).toBe('text');
    expect(classifyHref('../doc/readme.markdown')).toBe('text');
    expect(classifyHref('log.txt')).toBe('text');
    expect(classifyHref('paper.pdf')).toBe('pdf');
  });

  it('ignores a fragment when deciding the extension', () => {
    expect(classifyHref('notes.md#section')).toBe('text');
    expect(classifyHref('paper.pdf#page=2')).toBe('pdf');
  });

  it('treats anything else as other', () => {
    expect(classifyHref('script.lua')).toBe('other');
    expect(classifyHref('archive.zip')).toBe('other');
    expect(classifyHref('')).toBe('other');
    expect(classifyHref(null)).toBe('other');
  });
});

describe('slugify', () => {
  it('matches GitHub-style heading slugs', () => {
    expect(slugify('Hello World')).toBe('hello-world');
    expect(slugify('Hello, World!')).toBe('hello-world');
    expect(slugify('  Spaced   Out  ')).toBe('spaced-out');
    expect(slugify('Already-Hyphenated')).toBe('already-hyphenated');
  });

  it('keeps non-ASCII letters rather than stripping them', () => {
    expect(slugify('Überschrift')).toBe('überschrift');
  });
});

describe('describeUrl', () => {
  it('splits host, path and query', () => {
    expect(describeUrl('https://example.com/a/b?x=1')).toEqual(['example.com', '/a/b', '? x=1']);
  });

  it('omits a bare root path', () => {
    expect(describeUrl('https://example.com/')).toEqual(['example.com']);
  });
});

describe('installLinkHover — anchor resolution', () => {
  let teardown: (() => void) | undefined;
  let mounted: HTMLElement | undefined;

  afterEach(() => {
    teardown?.();
    teardown = undefined;
    // The container must leave the document, not just be forgotten: jsdom
    // resolves `#id` selectors through getElementById and then checks
    // containment, so a leftover container from a previous test makes the
    // next test's identically-id'd anchor resolve to null.
    mounted?.remove();
    mounted = undefined;
    document.getElementById('mdview-link-hover')?.remove();
    vi.useRealTimers();
  });

  /**
   * Build a container shaped like the real rendered output: headings carry
   * `data-sourcepos` (which docModel keys off) and, deliberately, NO id
   * attributes -- the WASM renderer emits none.
   */
  function container(): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = [
      '<h1 data-sourcepos="1:1-1:8">Title</h1>',
      '<p data-sourcepos="3:1-3:5">intro</p>',
      '<h2 data-sourcepos="5:1-5:16">Second Section</h2>',
      '<p data-sourcepos="7:1-7:9">body text</p>',
      '<a href="#second-section" id="lnk">jump</a>',
      '<a href="#nope" id="broken">jump</a>',
    ].join('');
    document.body.appendChild(el);
    mounted = el;
    return el;
  }

  function hover(el: HTMLElement, id: string): void {
    const anchor = el.querySelector<HTMLAnchorElement>(`#${id}`)!;
    anchor.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
  }

  function popupText(): string {
    return document.getElementById('mdview-link-hover')?.textContent ?? '';
  }

  it('resolves an anchor by heading slug, without relying on element ids', () => {
    vi.useFakeTimers();
    const el = container();
    // Guard the premise: if the fixture ever grows ids, this test would stop
    // proving that slug matching is what does the work.
    expect(el.querySelector('h2')?.hasAttribute('id')).toBe(false);

    teardown = installLinkHover(el, { key: 'k', token: 't', delayMs: 1 });
    hover(el, 'lnk');
    vi.advanceTimersByTime(5);

    const text = popupText();
    expect(text).toContain('Second Section');
    expect(text).toContain('body text');
  });

  it('stops the section at the next heading', () => {
    vi.useFakeTimers();
    const el = container();
    teardown = installLinkHover(el, { key: 'k', token: 't', delayMs: 1 });
    hover(el, 'lnk');
    vi.advanceTimersByTime(5);

    // "Title"/"intro" precede the target heading and must not leak in.
    expect(popupText()).not.toContain('intro');
  });

  it('reports an anchor that matches no heading', () => {
    vi.useFakeTimers();
    const el = container();
    teardown = installLinkHover(el, { key: 'k', token: 't', delayMs: 1 });
    hover(el, 'broken');
    vi.advanceTimersByTime(5);

    expect(popupText()).toContain('no heading matches');
  });

  it('opens nothing before the delay has elapsed', () => {
    vi.useFakeTimers();
    const el = container();
    teardown = installLinkHover(el, { key: 'k', token: 't', delayMs: 50 });
    hover(el, 'lnk');
    vi.advanceTimersByTime(10);

    expect(document.getElementById('mdview-link-hover')).toBeNull();
  });

  it('teardown removes the popup and stops listening', () => {
    vi.useFakeTimers();
    const el = container();
    const stop = installLinkHover(el, { key: 'k', token: 't', delayMs: 1 });
    hover(el, 'lnk');
    vi.advanceTimersByTime(5);
    expect(document.getElementById('mdview-link-hover')).not.toBeNull();

    stop();
    expect(document.getElementById('mdview-link-hover')).toBeNull();

    hover(el, 'lnk');
    vi.advanceTimersByTime(5);
    expect(document.getElementById('mdview-link-hover')).toBeNull();
  });
});

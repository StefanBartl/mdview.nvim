// tests/client/linkHover.test.ts
// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  classifyHref,
  describeUrl,
  slugify,
  headingAnchors,
  resolveAnchor,
  installLinkHover,
} from '../../src/client/render/linkHover';

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

describe('headingAnchors / resolveAnchor', () => {
  function doc(html: string): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = html;
    return el;
  }

  it('numbers a repeated slug the way GitHub does', () => {
    const list = headingAnchors(
      doc('<h2>Setup</h2><p>a</p><h2>Setup</h2><p>b</p><h3>Setup</h3><h2>Other</h2>'),
    );
    expect(list.map(h => h.anchor)).toEqual(['setup', 'setup-1', 'setup-2', 'other']);
  });

  it('resolves #slug-N to the N-th repeated heading', () => {
    const el = doc('<h2>Setup</h2><h2>Setup</h2><h2>Setup</h2>');
    const hs = Array.from(el.querySelectorAll('h2'));
    const list = headingAnchors(el);
    expect(resolveAnchor(list, 'setup')?.el).toBe(hs[0]);
    expect(resolveAnchor(list, 'setup-1')?.el).toBe(hs[1]);
    expect(resolveAnchor(list, 'setup-2')?.el).toBe(hs[2]);
    expect(resolveAnchor(list, 'setup-3')).toBeUndefined();
  });

  it('lets a heading really called "Setup-1" win over the number', () => {
    const el = doc('<h2>Setup</h2><h2>Setup</h2><h2 id="real">Setup-1</h2>');
    const target = resolveAnchor(headingAnchors(el), 'setup-1');
    expect(target?.el.id).toBe('real');
  });

  it('counts headings inside block quotes and list items', () => {
    const el = doc(
      [
        '<h2 data-sourcepos="1:1-1:8">Setup</h2>',
        '<blockquote data-sourcepos="3:1-3:10"><h2>Setup</h2></blockquote>',
        '<ul data-sourcepos="5:1-5:10"><li><h3>Setup</h3></li></ul>',
        '<h2 data-sourcepos="7:1-7:8" id="top">Setup</h2>',
      ].join(''),
    );
    const list = headingAnchors(el);
    expect(list.map(h => h.anchor)).toEqual(['setup', 'setup-1', 'setup-2', 'setup-3']);
    // The fourth top-level heading is #setup-3, not #setup-1.
    expect(resolveAnchor(list, 'setup-3')?.el.id).toBe('top');
  });

  it('gives a heading without slug text no anchor and does not count it', () => {
    const list = headingAnchors(doc('<h2>!!!</h2><h2>???</h2><h2>Setup</h2>'));
    expect(list.map(h => h.anchor)).toEqual(['setup']);
    expect(resolveAnchor(list, '-1')).toBeUndefined();
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

  it('follows a numbered #slug-N link into a nested heading', () => {
    vi.useFakeTimers();
    const el = document.createElement('div');
    el.innerHTML = [
      '<h2 data-sourcepos="1:1-1:8">Setup</h2>',
      '<p data-sourcepos="2:1-2:5">first</p>',
      '<blockquote data-sourcepos="4:1-5:10"><h2>Setup</h2><p>quoted body</p></blockquote>',
      '<a href="#setup-1" id="num">jump</a>',
    ].join('');
    document.body.appendChild(el);
    mounted = el;
    teardown = installLinkHover(el, { key: 'k', token: 't', delayMs: 1 });
    hover(el, 'num');
    vi.advanceTimersByTime(5);

    const text = popupText();
    expect(text).toContain('quoted body');
    expect(text).not.toContain('first');
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

// tests/client/localImages.test.ts
// @vitest-environment jsdom
import { describe, it, expect } from 'vitest';
import { isLocalImageSrc, resolveLocalImages } from '../../src/client/render/localImages';

describe('isLocalImageSrc', () => {
  it('treats relative image paths as local', () => {
    expect(isLocalImageSrc('photo.png')).toBe(true);
    expect(isLocalImageSrc('./assets/photo.png')).toBe(true);
    expect(isLocalImageSrc('../assets/photo.png')).toBe(true);
  });
  it('leaves scheme/protocol-relative/absolute/data/empty alone', () => {
    expect(isLocalImageSrc('https://example.com/x.png')).toBe(false);
    expect(isLocalImageSrc('data:image/png;base64,AAAA')).toBe(false);
    expect(isLocalImageSrc('//cdn.example.com/x.png')).toBe(false);
    expect(isLocalImageSrc('/root/abs.png')).toBe(false);
    expect(isLocalImageSrc('')).toBe(false);
    expect(isLocalImageSrc(null)).toBe(false);
  });
});

describe('resolveLocalImages', () => {
  function root(html: string): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = html;
    return el;
  }

  it('rewrites a relative img src to the /asset route', () => {
    const el = root('<img src="assets/photo.png" id="local">');
    resolveLocalImages(el, 'session-1', 'tok');
    const src = el.querySelector('#local')!.getAttribute('src')!;
    expect(src).toBe('/asset?key=session-1&path=assets%2Fphoto.png&token=tok');
  });

  it('leaves a remote/data img src untouched', () => {
    const el = root(
      '<img src="https://example.com/x.png" id="remote">' + '<img src="data:image/png;base64,AAAA" id="data">',
    );
    resolveLocalImages(el, 'session-1', 'tok');
    expect(el.querySelector('#remote')!.getAttribute('src')).toBe('https://example.com/x.png');
    expect(el.querySelector('#data')!.getAttribute('src')).toBe('data:image/png;base64,AAAA');
  });

  it('is a no-op without both key and token', () => {
    const el = root('<img src="photo.png" id="local">');
    resolveLocalImages(el, null, 'tok');
    expect(el.querySelector('#local')!.getAttribute('src')).toBe('photo.png');
    resolveLocalImages(el, 'session-1', null);
    expect(el.querySelector('#local')!.getAttribute('src')).toBe('photo.png');
  });
});

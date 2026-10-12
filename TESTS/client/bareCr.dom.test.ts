// @vitest-environment jsdom
//
// A document with a lone "\r" is not edited from the preview: the renderer
// counts that "\r" as a line ending, the relay and Neovim do not, so the block
// line numbers would point at other lines of the source. A CR that ends the text
// (a CRLF file Neovim loaded as "unix") moves nothing and is fine.

import { afterEach, describe, it, expect, vi } from 'vitest';
import {
  BARE_CR_MESSAGE,
  hasBareCr,
  installBlockEdit,
  splitLines,
} from '../../src/client/render/blockEdit';

afterEach(() => {
  document.body.innerHTML = '';
});

describe('hasBareCr', () => {
  it('is false for LF and CRLF documents', () => {
    expect(hasBareCr('a\nb\n')).toBe(false);
    expect(hasBareCr('a\r\nb\r\n')).toBe(false);
    expect(hasBareCr('a\r\nb\nc')).toBe(false);
    expect(hasBareCr('')).toBe(false);
  });

  it('lets a CR that ends the text pass', () => {
    expect(hasBareCr('a\r')).toBe(false);
    expect(hasBareCr('a\r\nb\r\nc\r')).toBe(false);
  });

  it('is true for a CR that is not followed by LF', () => {
    expect(hasBareCr('a\rb')).toBe(true);
    expect(hasBareCr('a\r\r')).toBe(true);
    expect(hasBareCr('a\r\r\nb')).toBe(true);
    expect(hasBareCr('a\r\nb\rc')).toBe(true);
  });
});

describe('splitLines and a CR that ends the text', () => {
  it('drops it from the last line only', () => {
    expect(splitLines('a\r\nb\r\nc\r')).toEqual(['a', 'b', 'c']);
    expect(splitLines('a\r\nb\r')).toEqual(['a', 'b']);
    expect(splitLines('a\r\nb')).toEqual(['a', 'b']);
  });
});

function setup(text: string, html = '<p data-sourcepos="1:1-1:1">a</p>') {
  const root = document.createElement('div');
  root.innerHTML = html;
  document.body.appendChild(root);
  const send = vi.fn();
  const notify = vi.fn();
  installBlockEdit(root, { getText: () => text, isEnabled: () => true, send, notify });
  return { root, send, notify };
}

function click(el: Element) {
  el.dispatchEvent(new window.MouseEvent('click', { bubbles: true, button: 0 }));
}

describe('block editor on a document with lone CRs', () => {
  it('opens no editor and says why', () => {
    const { root, send, notify } = setup('a\rb');
    click(root.querySelector('p')!);
    expect(root.querySelector('.mdview-block-editor')).toBeNull();
    expect(notify).toHaveBeenCalledWith(BARE_CR_MESSAGE);
    expect(send).not.toHaveBeenCalled();
  });

  it('still opens one on a CRLF document', () => {
    const { root, notify } = setup('a\r\nb');
    click(root.querySelector('p')!);
    expect(root.querySelector('.mdview-block-editor')).not.toBeNull();
    expect(notify).not.toHaveBeenCalled();
  });

  it('opens one on the last block of a CRLF document loaded as unix, without the CR', () => {
    const { root, notify } = setup('a\r\nb\r\nc\r', '<p data-sourcepos="3:1-3:1">c</p>');
    click(root.querySelector('p')!);
    const field = root.querySelector('.mdview-block-editor') as HTMLTextAreaElement;
    expect(field).not.toBeNull();
    expect(field.value).toBe('c');
    expect(notify).not.toHaveBeenCalled();
  });
});

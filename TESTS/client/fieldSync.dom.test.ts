// tests/client/fieldSync.dom.test.ts
// @vitest-environment jsdom
//
// Real-DOM test for text-field sync: committing an edit on a named input/
// textarea calls send(name, value); unnamed fields, checkboxes and radios are
// ignored; commit is on `change` (blur), not per keystroke.

import { describe, it, expect, vi } from 'vitest';
import { isSyncableField, installFieldSync } from '../../src/client/render/fieldSync';

function setup(html: string) {
  const root = document.createElement('div');
  root.innerHTML = html;
  document.body.appendChild(root);
  return root;
}

describe('isSyncableField', () => {
  it('accepts a named text input and textarea', () => {
    const root = setup('<input type="text" name="a"><textarea name="b"></textarea>');
    expect(isSyncableField(root.querySelector('input'))).toBe(true);
    expect(isSyncableField(root.querySelector('textarea'))).toBe(true);
  });

  it('accepts an input with no explicit type (defaults to text)', () => {
    const root = setup('<input name="a">');
    expect(isSyncableField(root.querySelector('input'))).toBe(true);
  });

  it('rejects unnamed, checkbox and radio inputs', () => {
    const root = setup('<input type="text"><input type="checkbox" name="c"><input type="radio" name="r">');
    const [text, cb, radio] = root.querySelectorAll('input');
    expect(isSyncableField(text)).toBe(false); // no name
    expect(isSyncableField(cb)).toBe(false);
    expect(isSyncableField(radio)).toBe(false);
  });
});

describe('installFieldSync (real DOM)', () => {
  it('sends name and value on change (commit)', () => {
    const root = setup('<input type="text" name="title" value="">');
    const send = vi.fn();
    installFieldSync(root, send);

    const input = root.querySelector('input')!;
    input.value = 'Hello';
    input.dispatchEvent(new window.Event('change', { bubbles: true }));

    expect(send).toHaveBeenCalledWith('title', 'Hello');
  });

  it('sends a textarea body', () => {
    const root = setup('<textarea name="notes">old</textarea>');
    const send = vi.fn();
    installFieldSync(root, send);

    const ta = root.querySelector('textarea')!;
    ta.value = 'line one\nline two';
    ta.dispatchEvent(new window.Event('change', { bubbles: true }));

    expect(send).toHaveBeenCalledWith('notes', 'line one\nline two');
  });

  it('does not fire on input events (only on change)', () => {
    const root = setup('<input type="text" name="a">');
    const send = vi.fn();
    installFieldSync(root, send);

    const input = root.querySelector('input')!;
    input.value = 'typing';
    input.dispatchEvent(new window.Event('input', { bubbles: true }));

    expect(send).not.toHaveBeenCalled();
  });

  it('ignores a checkbox change (that is taskToggle territory)', () => {
    const root = setup('<input type="checkbox" name="c">');
    const send = vi.fn();
    installFieldSync(root, send);

    const cb = root.querySelector('input')!;
    cb.dispatchEvent(new window.Event('change', { bubbles: true }));

    expect(send).not.toHaveBeenCalled();
  });
});

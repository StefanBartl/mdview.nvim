// @vitest-environment jsdom
//
// Real-DOM test for block editing: a click on a rendered block swaps it for a
// field holding its source lines; a changed commit sends {start, end, expected,
// text}; an unchanged one, Escape and clicks on links/controls send nothing.

import { describe, it, expect, vi } from 'vitest';
import {
  blockAt,
  installBlockEdit,
  parseSourcePos,
  rangeOf,
  sliceLines,
  trimBlankTail,
} from '../../src/client/render/blockEdit';

const DOC = ['# Title', '', 'first line', 'second line', '', '- item one', '  - nested', '- item two'].join('\n');

function setup(enabled = true, text = DOC) {
  const root = document.createElement('div');
  root.innerHTML =
    '<h1 data-sourcepos="1:1-1:7">Title</h1>' +
    '<p data-sourcepos="3:1-4:11">first line\nsecond <a href="x.md">link</a></p>' +
    '<ul data-sourcepos="6:1-8:10">' +
    '<li data-sourcepos="6:1-7:11">item one<ul data-sourcepos="7:3-7:11"><li data-sourcepos="7:3-7:11">nested</li></ul></li>' +
    '<li data-sourcepos="8:1-8:10">item two</li>' +
    '</ul>';
  document.body.appendChild(root);
  const send = vi.fn();
  const onClose = vi.fn();
  const state = { enabled };
  const editor = installBlockEdit(root, {
    getText: () => text,
    isEnabled: () => state.enabled,
    send,
    onClose,
  });
  return { root, send, onClose, editor, state };
}

function click(el: Element) {
  el.dispatchEvent(new window.MouseEvent('click', { bubbles: true, button: 0 }));
}

function key(el: Element, init: KeyboardEventInit) {
  el.dispatchEvent(new window.KeyboardEvent('keydown', { bubbles: true, ...init }));
}

describe('parseSourcePos / rangeOf / sliceLines', () => {
  it('parses comrak positions and refuses malformed ones', () => {
    expect(parseSourcePos('3:1-4:11')).toEqual({ start: 3, end: 4 });
    expect(parseSourcePos('x')).toBeNull();
    expect(parseSourcePos('4:1-3:2')).toBeNull();
    expect(parseSourcePos(null)).toBeNull();
  });

  it('cuts a list item at its first nested list', () => {
    const { root } = setup();
    const li = root.querySelector('li')!;
    expect(rangeOf(li)).toEqual({ start: 6, end: 6 });
  });

  it('slices lines inclusively and refuses a range past the end', () => {
    expect(sliceLines(DOC, { start: 3, end: 4 })).toBe('first line\nsecond line');
    expect(sliceLines(DOC, { start: 9, end: 9 })).toBeNull();
  });

  it('reads CRLF as one line break and takes already split lines', () => {
    expect(sliceLines('a\r\nb\r\nc', { start: 2, end: 3 })).toBe('b\nc');
    expect(sliceLines(['a', 'b', 'c'], { start: 1, end: 2 })).toBe('a\nb');
  });
});

describe('trimBlankTail', () => {
  it('drops the blank lines a block position runs through', () => {
    expect(trimBlankTail('- a\n- b\n\nTail', { start: 2, end: 3 })).toEqual({ start: 2, end: 2 });
    expect(trimBlankTail('a\n\n\nb', { start: 1, end: 3 })).toEqual({ start: 1, end: 1 });
  });

  it('keeps a range that ends on text and never goes below the start', () => {
    expect(trimBlankTail('a\nb', { start: 1, end: 2 })).toEqual({ start: 1, end: 2 });
    expect(trimBlankTail('\n\n', { start: 2, end: 3 })).toEqual({ start: 2, end: 2 });
  });
});

describe('blockAt', () => {
  it('finds the block, not links or the gap between blocks', () => {
    const { root } = setup();
    expect(blockAt(root.querySelector('h1'), root)?.tagName).toBe('H1');
    expect(blockAt(root.querySelector('a'), root)).toBeNull();
    expect(blockAt(root.querySelector('ul'), root)).toBeNull();
    expect(blockAt(root.querySelectorAll('li')[2], root)?.textContent).toBe('item two');
  });
});

describe('installBlockEdit (real DOM)', () => {
  it('opens a one-line input for a heading and sends a changed commit', () => {
    const { root, send, onClose } = setup();
    click(root.querySelector('h1')!);

    const field = root.querySelector('.mdview-block-editor') as HTMLInputElement;
    expect(field.tagName).toBe('INPUT');
    expect(field.value).toBe('# Title');
    expect((root.querySelector('h1') as HTMLElement).style.display).toBe('none');

    field.value = '# New title';
    key(field, { key: 'Enter' });

    expect(send).toHaveBeenCalledWith({ start: 1, end: 1, expected: '# Title', text: '# New title' });
    expect(root.querySelector('.mdview-block-editor')).toBeNull();
    expect((root.querySelector('h1') as HTMLElement).style.display).toBe('');
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('opens a textarea for a multi-line block and commits on Ctrl+Enter', () => {
    const { root, send } = setup();
    click(root.querySelector('p')!);

    const field = root.querySelector('.mdview-block-editor') as HTMLTextAreaElement;
    expect(field.tagName).toBe('TEXTAREA');
    expect(field.value).toBe('first line\nsecond line');

    field.value = 'only one';
    // plain Enter is a newline in a textarea: no commit
    key(field, { key: 'Enter' });
    expect(send).not.toHaveBeenCalled();
    key(field, { key: 'Enter', ctrlKey: true });
    expect(send).toHaveBeenCalledWith({
      start: 3,
      end: 4,
      expected: 'first line\nsecond line',
      text: 'only one',
    });
  });

  it('commits on blur (focus moving elsewhere), once', () => {
    const { root, send } = setup();
    click(root.querySelector('h1')!);
    const field = root.querySelector('.mdview-block-editor') as HTMLInputElement;
    expect(document.activeElement).toBe(field);
    field.value = '# B';
    field.blur(); // real blur: focus leaves the field
    expect(send).toHaveBeenCalledTimes(1);
    expect(send).toHaveBeenCalledWith({ start: 1, end: 1, expected: '# Title', text: '# B' });
  });

  it('does not commit half-typed text when only the window lost focus', () => {
    const { root, send, editor } = setup();
    click(root.querySelector('h1')!);
    const field = root.querySelector('.mdview-block-editor') as HTMLInputElement;
    field.value = '# half typed';
    // alt-tab: the blur event fires but the field stays the active element
    field.dispatchEvent(new window.FocusEvent('blur'));
    expect(send).not.toHaveBeenCalled();
    expect(editor.isEditing()).toBe(true);
  });

  it('ignores Enter that confirms an IME composition', () => {
    const { root, send } = setup();
    click(root.querySelector('h1')!);
    const field = root.querySelector('.mdview-block-editor') as HTMLInputElement;
    field.value = '# composed';
    key(field, { key: 'Enter', isComposing: true });
    expect(send).not.toHaveBeenCalled();
    key(field, { key: 'Enter' });
    expect(send).toHaveBeenCalledTimes(1);
  });

  it('labels the field for assistive technology', () => {
    const { root } = setup();
    click(root.querySelector('h1')!);
    expect(root.querySelector('.mdview-block-editor')!.getAttribute('aria-label')).toBeTruthy();
  });

  it('never opens inside a private block (the click is its reveal gesture)', () => {
    const { root } = setup();
    const priv = document.createElement('div');
    priv.setAttribute('data-private', '');
    priv.innerHTML = '<p data-sourcepos="3:1-4:11">hidden words</p>';
    root.appendChild(priv);
    click(priv.querySelector('p')!);
    expect(root.querySelector('.mdview-block-editor')).toBeNull();
  });

  it('sends nothing for an unchanged commit and for Escape', () => {
    const { root, send, onClose } = setup();
    click(root.querySelector('h1')!);
    key(root.querySelector('.mdview-block-editor')!, { key: 'Enter' });

    click(root.querySelector('h1')!);
    const field = root.querySelector('.mdview-block-editor') as HTMLInputElement;
    field.value = 'changed but cancelled';
    key(field, { key: 'Escape' });

    expect(send).not.toHaveBeenCalled();
    expect(onClose).toHaveBeenCalledTimes(2);
    expect(root.querySelector('.mdview-block-editor')).toBeNull();
  });

  it('does nothing when disabled, on links, or with a modifier key', () => {
    const off = setup(false);
    click(off.root.querySelector('h1')!);
    expect(off.root.querySelector('.mdview-block-editor')).toBeNull();

    const on = setup();
    click(on.root.querySelector('a')!);
    on.root
      .querySelector('h1')!
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true, button: 0, ctrlKey: true }));
    expect(on.root.querySelector('.mdview-block-editor')).toBeNull();
  });

  it('reports editing state and cancels without sending', () => {
    const { root, send, editor } = setup();
    expect(editor.isEditing()).toBe(false);
    click(root.querySelector('h1')!);
    expect(editor.isEditing()).toBe(true);
    editor.cancel();
    expect(editor.isEditing()).toBe(false);
    expect(send).not.toHaveBeenCalled();
  });

  it('refuses to open when the rendered lines are not in the text', () => {
    const { root } = setup(true, '# Title');
    click(root.querySelector('p')!); // lines 3-4 do not exist in the one-line text
    expect(root.querySelector('.mdview-block-editor')).toBeNull();
  });
});

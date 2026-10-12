// tests/client/taskToggle.dom.test.ts
// @vitest-environment jsdom
//
// Real-DOM test for the task-list checkbox sync: toggling a checkbox must
// resolve its 1-based source line from the enclosing li[data-sourcepos] and
// call send(line, checked); a checkbox with no resolvable source line is
// reverted rather than sent.

import { describe, it, expect, vi } from 'vitest';
import { sourceLineOf, enableTaskCheckboxes, installTaskToggle } from '../../src/client/render/taskToggle';

// The exact shape comrak emits for "- [ ] alpha" / "- [x] beta", with
// data-sourcepos on the <li>.
const TASK_HTML = `
  <ul>
    <li data-sourcepos="3:1-3:11"><input type="checkbox" disabled> alpha</li>
    <li data-sourcepos="4:1-4:10"><input type="checkbox" checked disabled> beta</li>
  </ul>`;

function setup(html: string) {
  const root = document.createElement('div');
  root.innerHTML = html;
  document.body.appendChild(root);
  return root;
}

describe('sourceLineOf', () => {
  it('reads the 1-based start line from data-sourcepos', () => {
    const el = document.createElement('li');
    el.setAttribute('data-sourcepos', '7:1-9:4');
    expect(sourceLineOf(el)).toBe(7);
  });

  it('returns null when the attribute is absent or malformed', () => {
    expect(sourceLineOf(null)).toBeNull();
    const el = document.createElement('li');
    expect(sourceLineOf(el)).toBeNull();
    el.setAttribute('data-sourcepos', 'nope');
    expect(sourceLineOf(el)).toBeNull();
  });
});

describe('enableTaskCheckboxes', () => {
  it('removes disabled and tags each task checkbox', () => {
    const root = setup(TASK_HTML);
    enableTaskCheckboxes(root);
    const boxes = root.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');
    expect(boxes.length).toBe(2);
    boxes.forEach((b) => {
      expect(b.disabled).toBe(false);
      expect(b.dataset.mdviewToggle).toBe('1');
    });
  });
});

describe('installTaskToggle (real DOM)', () => {
  it('sends the source line and new checked state on toggle', () => {
    const root = setup(TASK_HTML);
    enableTaskCheckboxes(root);
    const send = vi.fn();
    installTaskToggle(root, send);

    const first = root.querySelector<HTMLInputElement>('input[type="checkbox"]')!;
    first.checked = true;
    first.dispatchEvent(new window.Event('change', { bubbles: true }));

    expect(send).toHaveBeenCalledWith(3, true);
  });

  it('sends checked=false when a ticked box is unticked', () => {
    const root = setup(TASK_HTML);
    enableTaskCheckboxes(root);
    const send = vi.fn();
    installTaskToggle(root, send);

    const beta = root.querySelectorAll<HTMLInputElement>('input[type="checkbox"]')[1];
    beta.checked = false;
    beta.dispatchEvent(new window.Event('change', { bubbles: true }));

    expect(send).toHaveBeenCalledWith(4, false);
  });

  it('reverts and does not send when the source line is unresolvable', () => {
    const root = setup('<ul><li><input type="checkbox"> orphan</li></ul>');
    enableTaskCheckboxes(root);
    const send = vi.fn();
    installTaskToggle(root, send);

    const box = root.querySelector<HTMLInputElement>('input[type="checkbox"]')!;
    box.checked = true;
    box.dispatchEvent(new window.Event('change', { bubbles: true }));

    expect(send).not.toHaveBeenCalled();
    expect(box.checked).toBe(false); // reverted
  });

  it('ignores changes on non-task checkboxes', () => {
    const root = setup('<input type="checkbox" id="loose">');
    const send = vi.fn();
    installTaskToggle(root, send);

    const box = root.querySelector<HTMLInputElement>('#loose')!;
    box.checked = true;
    box.dispatchEvent(new window.Event('change', { bubbles: true }));

    expect(send).not.toHaveBeenCalled();
  });
});

describe('installTaskToggle, a refused toggle', () => {
  const flush = () => new Promise(resolve => setTimeout(resolve, 0));
  function toggle(root: HTMLElement, send: () => Promise<boolean>) {
    enableTaskCheckboxes(root);
    installTaskToggle(root, send);
    const box = root.querySelector<HTMLInputElement>('input[type="checkbox"]')!;
    box.checked = true;
    box.dispatchEvent(new window.Event('change', { bubbles: true }));
    return box;
  }

  it('puts the box back when send resolves false', async () => {
    const box = toggle(setup(TASK_HTML), () => Promise.resolve(false));
    expect(box.checked).toBe(true);
    await flush();
    expect(box.checked).toBe(false);
  });

  it('leaves the box alone when send resolves true', async () => {
    const box = toggle(setup(TASK_HTML), () => Promise.resolve(true));
    await flush();
    expect(box.checked).toBe(true);
  });

  it('does not touch a box that a re-render removed meanwhile', async () => {
    const root = setup(TASK_HTML);
    const box = toggle(root, () => Promise.resolve(false));
    root.innerHTML = '';
    await flush();
    expect(box.checked).toBe(true);
  });
});

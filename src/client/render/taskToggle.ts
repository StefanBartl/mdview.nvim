// src/client/render/taskToggle.ts
//
// GFM task-list checkbox sync. comrak renders `- [ ]` / `- [x]` as a disabled
// <input type="checkbox"> inside an <li> that carries data-sourcepos. This
// module makes those checkboxes interactive and, on toggle, sends the checkbox's
// 1-based source line and new state to the relay's /toggle bridge — which either
// rewrites the source file (standalone mode) or hands it to Neovim to edit the
// buffer (Neovim-driven mode). Either way the change flows back through the
// normal push path, so the box stays ticked because the *source* now says so.

/**
 * Parse the 1-based start line out of a data-sourcepos value
 * ("startLine:startCol-endLine:endCol"). The checkbox always sits on the item's
 * first line, so the start line is the line to toggle. Returns null if absent or
 * malformed.
 */
export function sourceLineOf(el: Element | null): number | null {
  const sp = el?.getAttribute?.('data-sourcepos');
  if (!sp) return null;
  const m = /^(\d+):/.exec(sp);
  if (!m) return null;
  const line = Number(m[1]);
  return Number.isInteger(line) && line >= 1 ? line : null;
}

/**
 * Enable every task-list checkbox under `root` (comrak emits them `disabled`)
 * and tag them so the delegated handler knows they're the syncable kind. Called
 * after each render, since innerHTML replaces the nodes.
 */
export function enableTaskCheckboxes(root: HTMLElement): void {
  const boxes = root.querySelectorAll<HTMLInputElement>('li > input[type="checkbox"]');
  boxes.forEach((box) => {
    box.disabled = false;
    box.dataset.mdviewToggle = '1';
  });
}

/**
 * Install one delegated change handler that, when a task-list checkbox is
 * toggled, resolves its source line and calls `send(line, checked)`. Delegated
 * on `root` (which survives the innerHTML swap), so it's installed once. A
 * checkbox with no resolvable source line is reverted rather than silently
 * desynced from the document.
 */
export function installTaskToggle(
  root: HTMLElement,
  send: (line: number, checked: boolean) => void,
): void {
  root.addEventListener('change', (ev: Event) => {
    const box = ev.target as HTMLInputElement | null;
    if (!box || box.dataset.mdviewToggle !== '1') return;

    const line = sourceLineOf(box.closest('[data-sourcepos]'));
    if (line === null) {
      // Can't map it back to the source — undo the visual change so the tab
      // doesn't drift out of sync with the document it mirrors.
      box.checked = !box.checked;
      return;
    }
    send(line, box.checked);
  });
}

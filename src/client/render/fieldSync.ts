// src/client/render/fieldSync.ts
//
// Syncable text fields. A `<input name="…">` or `<textarea name="…">` in the
// Markdown source renders as an editable field; when the user commits an edit
// its new value is sent to the relay's /field bridge, which rewrites the value
// in the source (matched by `name`, since raw HTML carries no data-sourcepos).
// The change flows back through the push path, so the value persists because the
// source now holds it.
//
// Commit happens on `change` (i.e. on blur / Enter), NOT on every keystroke: a
// write-back triggers a re-render that replaces the DOM, which would yank the
// field out from under someone still typing. Committing when they leave the
// field keeps typing uninterrupted while still persisting the result.

/**
 * Is this element a syncable text field — a named text input or textarea?
 * Checkboxes (handled by taskToggle) and unnamed fields are excluded.
 */
export function isSyncableField(el: Element | null): el is HTMLInputElement | HTMLTextAreaElement {
  if (!el) return false;
  const name = el.getAttribute('name');
  if (!name) return false;
  if (el.tagName === 'TEXTAREA') return true;
  if (el.tagName === 'INPUT') {
    const type = (el.getAttribute('type') || 'text').toLowerCase();
    return type !== 'checkbox' && type !== 'radio';
  }
  return false;
}

/**
 * Install one delegated `change` handler that, when a syncable field is
 * committed, calls `send(name, value)`. Delegated on `root` (which survives the
 * innerHTML swap), so it's installed once.
 */
export function installFieldSync(
  root: HTMLElement,
  send: (name: string, value: string) => void,
): void {
  root.addEventListener('change', (ev: Event) => {
    const el = ev.target as Element | null;
    if (!isSyncableField(el)) return;
    const name = el.getAttribute('name');
    if (!name) return;
    send(name, el.value);
  });
}

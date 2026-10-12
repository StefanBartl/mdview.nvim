// src/client/render/toast.ts
//
// A short message for the person at the preview ("Not saved: …"). One
// persistent live region whose text is replaced, so a second message does not
// pile up on top of the first and a screen reader announces each change (a
// freshly inserted element is often skipped). The text is set as text, never as
// markup: some messages come from Neovim.

const ID = 'mdview-toast';
const MAX_LENGTH = 200;
const SHOW_MS = 4000;

let timer: ReturnType<typeof setTimeout> | null = null;

/** Show `message` for a few seconds. */
export function showToast(message: string, doc: Document = document): void {
  let el = doc.getElementById(ID);
  if (!el) {
    el = doc.createElement('div');
    el.id = ID;
    el.className = 'mdview-toast';
    el.setAttribute('role', 'status');
    el.setAttribute('aria-live', 'polite');
    doc.body.appendChild(el);
  }
  el.textContent = message.slice(0, MAX_LENGTH);
  el.classList.add('mdview-toast-on');

  if (timer !== null) clearTimeout(timer);
  timer = setTimeout(() => {
    const shown = doc.getElementById(ID);
    if (shown) {
      shown.classList.remove('mdview-toast-on');
      shown.textContent = '';
    }
    timer = null;
  }, SHOW_MS);
}

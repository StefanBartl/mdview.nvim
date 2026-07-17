// src/client/render/history.ts
//
// Browser Back/Forward for the preview. The preview swaps documents in place
// (same URL, content pushed over the socket), so the browser has no history to
// go back through. Neovim sends a "document changed" ping per document; we push
// a history entry for each, and on popstate (Back/Forward) ask Neovim to reopen
// the target document. The distinction between a user-driven change (push a new
// entry) and a Back/Forward-driven change (don't push, or we'd loop) is tracked
// via a flag set right before we request the popstate navigation.

export interface HistoryDeps {
  /** Ask Neovim to open (an absolute path to) a document. */
  navigateTo: (absPath: string) => void;
}

let currentDoc: string | null = null;
let viaPopstate = false;
let handler: ((ev: PopStateEvent) => void) | null = null;

/** Install the popstate handler and reset state. Idempotent. Call once at boot. */
export function installHistory(deps: HistoryDeps): void {
  currentDoc = null;
  viaPopstate = false;
  if (handler) window.removeEventListener('popstate', handler);
  handler = (ev: PopStateEvent) => {
    const st = ev.state as { mdviewDoc?: string } | null;
    const target = st?.mdviewDoc;
    if (target && target !== currentDoc) {
      viaPopstate = true; // the resulting doc-change ping must not push a new entry
      deps.navigateTo(target);
    }
  };
  window.addEventListener('popstate', handler);
}

/** Record that the previewed document changed to `path` (from a doc ping). */
export function onDocChange(path: string): void {
  if (!path || path === currentDoc) return;
  if (viaPopstate) {
    viaPopstate = false; // this change was Back/Forward — don't push again
  } else if (currentDoc === null) {
    history.replaceState({ mdviewDoc: path }, ''); // first document = base entry
  } else {
    history.pushState({ mdviewDoc: path }, ''); // user navigated to a new document
  }
  currentDoc = path;
}

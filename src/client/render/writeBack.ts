// src/client/render/writeBack.ts
//
// The URL of a browser -> source write-back (/toggle, /field, /edit).
//
// Every one of them names two things: `key`, the room of this tab, and `doc`,
// the document the tab is showing. They differ under `browser.behavior =
// "reuse"`: one tab follows the active buffer, so its room is the path of the
// first document for the whole session while the document on screen changes.
// The relay's standalone mode matches on the room; Neovim edits the buffer of
// the document.

export interface WriteBackTarget {
  /** The session token (`?token=`). */
  token: string;
  /** The room of this tab (`?key=`). */
  key: string;
  /** The document on screen, when Neovim has announced one (see `currentDocument`). */
  doc?: string | null;
}

/** `/toggle?token=…&key=…[&doc=…]`, every value encoded. */
export function writeBackUrl(route: string, target: WriteBackTarget): string {
  let url = `${route}?token=${encodeURIComponent(target.token)}&key=${encodeURIComponent(target.key)}`;
  if (target.doc) url += `&doc=${encodeURIComponent(target.doc)}`;
  return url;
}

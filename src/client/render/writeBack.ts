// src/client/render/writeBack.ts
//
// The URL and the answer of a browser -> source write-back (/toggle, /field,
// /edit).
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
  /**
   * The source line a checkbox toggle was computed against, without its line
   * ending: if an edit moved the lines in between, the toggle is dropped
   * instead of ticking the neighbour.
   */
  expected?: string | null;
}

/** `/toggle?token=…&key=…[&doc=…][&expected=…]`, every value encoded. */
export function writeBackUrl(route: string, target: WriteBackTarget): string {
  let url = `${route}?token=${encodeURIComponent(target.token)}&key=${encodeURIComponent(target.key)}`;
  if (target.doc) url += `&doc=${encodeURIComponent(target.doc)}`;
  if (target.expected) url += `&expected=${encodeURIComponent(target.expected)}`;
  return url;
}

/** What became of a write-back, for the message shown to the person editing. */
export type WriteBackResult = 'ok' | 'stale' | 'readonly' | 'too-large' | 'refused' | 'offline';

/** The text shown for a result that is not `ok`. */
export const WRITE_BACK_MESSAGES: Record<Exclude<WriteBackResult, 'ok'>, string> = {
  stale: 'Not saved: those lines changed in the source meanwhile.',
  readonly: 'Not saved: the file is read-only.',
  'too-large': 'Not saved: the block is too large to send.',
  refused: 'Not saved: the edit was refused.',
  offline: 'Not saved: the preview server did not answer.',
};

/** Map an HTTP status of a write-back to a result. */
export function resultOfStatus(status: number): WriteBackResult {
  if (status >= 200 && status < 300) return 'ok';
  if (status === 409) return 'stale';
  if (status === 403) return 'readonly';
  if (status === 413) return 'too-large';
  return 'refused';
}

/**
 * POST a JSON body and say what became of it. Never rejects: a network failure
 * is `offline`. `fetchFn` is injectable so the mapping can be tested.
 */
export async function postJson(
  fetchFn: typeof fetch,
  url: string,
  body: unknown,
): Promise<WriteBackResult> {
  try {
    const res = await fetchFn(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    return resultOfStatus(res.status);
  } catch {
    return 'offline';
  }
}

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

/**
 * The longest `expected` line (in bytes) the relay takes in a URL (see
 * maxExpectedLen in native/server/main.go). A longer one is left out: the tick
 * is then applied without the stale-line guard instead of being refused.
 */
export const MAX_EXPECTED_BYTES = 2048;

/** `/toggle?token=…&key=…[&doc=…][&expected=…]`, every value encoded. */
export function writeBackUrl(route: string, target: WriteBackTarget): string {
  let url = `${route}?token=${encodeURIComponent(target.token)}&key=${encodeURIComponent(target.key)}`;
  if (target.doc) url += `&doc=${encodeURIComponent(target.doc)}`;
  if (target.expected && new TextEncoder().encode(target.expected).length <= MAX_EXPECTED_BYTES) {
    url += `&expected=${encodeURIComponent(target.expected)}`;
  }
  return url;
}

/** What became of a write-back, for the message shown to the person editing. */
export type WriteBackResult = 'ok' | 'stale' | 'readonly' | 'too-large' | 'refused' | 'offline';

/** The text shown for a result that is not `ok`. */
export const WRITE_BACK_MESSAGES: Record<Exclude<WriteBackResult, 'ok'>, string> = {
  stale: 'Not saved: those lines changed in the source meanwhile.',
  readonly: 'Not saved: the file is read-only.',
  'too-large': 'Not saved: the block is too large to send.',
  // 403 is also a missing --edit or a wrong token: say only what is known.
  refused: 'Not saved: the preview server refused the change.',
  offline: 'Not saved: the preview server did not answer.',
};

/**
 * Map an HTTP status of a write-back to a result. A 403 means "the file is
 * read-only" only when the relay says so in its answer; without --edit or with
 * a wrong token it is a plain refusal.
 */
export function resultOfStatus(status: number, body = ''): WriteBackResult {
  if (status >= 200 && status < 300) return 'ok';
  if (status === 409) return 'stale';
  if (status === 403 && body.includes('read-only')) return 'readonly';
  if (status === 413) return 'too-large';
  return 'refused';
}

async function post(
  fetchFn: typeof fetch,
  url: string,
  body: string,
  contentType: string,
  keepalive: boolean,
): Promise<WriteBackResult> {
  try {
    const res = await fetchFn(url, {
      method: 'POST',
      headers: { 'Content-Type': contentType },
      body,
      keepalive,
    });
    return resultOfStatus(res.status, res.status === 403 ? await res.text() : '');
  } catch {
    return 'offline';
  }
}

/**
 * POST a JSON body and say what became of it. Never rejects: a network failure
 * is `offline`. `fetchFn` is injectable so the mapping can be tested.
 * `keepalive` lets a small request outlive the page (not for large bodies).
 */
export function postJson(
  fetchFn: typeof fetch,
  url: string,
  body: unknown,
  keepalive = false,
): Promise<WriteBackResult> {
  return post(fetchFn, url, JSON.stringify(body), 'application/json', keepalive);
}

/** `postJson` for a plain-text body (the "<line>:<0|1>" of a checkbox toggle). */
export function postText(
  fetchFn: typeof fetch,
  url: string,
  body: string,
  keepalive = false,
): Promise<WriteBackResult> {
  return post(fetchFn, url, body, 'text/plain', keepalive);
}

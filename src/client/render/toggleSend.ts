// src/client/render/toggleSend.ts
//
// Sending a checkbox toggle: the guard against a document whose line numbers do
// not match the source, the stale-line check (`expected`), and the request.

import { hasBareCr, splitLines } from './blockEdit';
import { postToggle, type WriteBackResult, type WriteBackTarget } from './writeBack';

/** The toggle was not sent: the document has lone CR line endings (see `hasBareCr`). */
export type ToggleResult = WriteBackResult | 'bare-cr';

/**
 * Tick or untick the checkbox on 1-based `line` of `text` (the text the DOM was
 * rendered from). The line as rendered goes along as `expected`: an edit applied
 * before this toggle may have moved the lines, and the receiving side then drops
 * it instead of ticking the neighbour. A document with lone CRs has other line
 * numbers in the preview than in the source, so nothing is sent for it.
 */
export function sendToggle(
  fetchFn: typeof fetch,
  target: Omit<WriteBackTarget, 'expected'>,
  text: string,
  line: number,
  checked: boolean,
): Promise<ToggleResult> {
  if (hasBareCr(text)) return Promise.resolve('bare-cr');
  const expected = splitLines(text)[line - 1] ?? null;
  return postToggle(fetchFn, { ...target, expected }, line, checked);
}

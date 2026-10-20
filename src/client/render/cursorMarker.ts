// src/client/render/cursorMarker.ts
//
// Shows where the Neovim cursor is, in the preview.
//
//  * "line"  (Stage A): a full-width band over the cursor's whole source line
//    (all its visual lines when it wraps), independent of the column. Exact
//    where the line's text is locatable (inline runs, code blocks), otherwise
//    the line's slice of its sourcepos block (see lineBand).
//
//  * "block": like "caret", but a box over the whole character under the cursor
//    (its own width; at the end of the line's text, one character wide), the way
//    a terminal's block cursor looks from a distance. Optional blinking comes from
//    setCursorBlink and is never shown under prefers-reduced-motion.
//
//  * "caret" (Stage C): a caret at the exact cursor character. The WASM renderer
//    wraps inline text/code runs in `<span data-sp="sl:sc:el:ec">` (byte columns,
//    matching Neovim's byte-based cursor column). We find the run containing the
//    cursor, convert the byte offset into it to a UTF-16 offset, and place a DOM
//    Range there to read the pixel position. Falls back to the line bar on blank
//    lines, inside code blocks, or wherever no run covers the column.
//
// See docs/Roadmap/KONZEPT_links_und_cursor.md.

import { pickScrollTarget, type ScrollTarget } from './scrollSync';
import { topLevelBlocks, sectionRange } from './docModel';
import {
  runsOnLine,
  byteOffsetToUtf16,
  findTextPosition,
  buildPosIndex,
  lineStartPosition,
  lineEndPosition,
} from './sourcePos';

export type CursorMarkerMode = 'off' | 'line' | 'caret' | 'block' | 'section';

export function parseCursorMarkerMode(param: string | null | undefined): CursorMarkerMode {
  if (param === 'off') return 'off';
  if (param === 'caret') return 'caret';
  if (param === 'block') return 'block';
  if (param === 'section') return 'section';
  return 'line';
}

/**
 * Whether `mode` places its marker from the inline source-position spans, so the
 * renderer has to emit them ("caret" and "block" both measure a character).
 */
export function cursorModeNeedsSourceMap(mode: CursorMarkerMode): boolean {
  return mode === 'caret' || mode === 'block';
}

/** Default blink period of the block marker, in ms (about a terminal cursor's). */
export const DEFAULT_BLINK_MS = 530;
const MIN_BLINK_MS = 100;
const MAX_BLINK_MS = 5000;

/**
 * The block marker's blink setting: `false` (steady) or the half-period in ms.
 * Accepts what the URL (`?blink=1|0|530`) and a control message (`true`, `false`,
 * a number) carry; anything else is steady.
 */
export function parseCursorBlink(value: unknown): false | number {
  if (value === true || value === '1' || value === 'true') return DEFAULT_BLINK_MS;
  const n = typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : NaN;
  if (Number.isFinite(n) && n > 0) {
    return Math.min(MAX_BLINK_MS, Math.max(MIN_BLINK_MS, Math.round(n)));
  }
  return false;
}

let blinkMs: false | number = false;

/** Set the block marker's blink (see parseCursorBlink); takes effect on the next placement. */
export function setCursorBlink(value: false | number): void {
  blinkMs = value;
}

/** Whether the visitor asked the OS for less motion: blinking is then never shown. */
function prefersReducedMotion(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  );
}

let barEl: HTMLElement | null = null;
let caretEl: HTMLElement | null = null;
let blockEl: HTMLElement | null = null;

function ensureEl(
  current: HTMLElement | null,
  container: HTMLElement,
  className: string,
): HTMLElement {
  // Re-create if it was wiped (innerHTML replace on re-render detaches it) or if
  // it belongs to a different container.
  if (!current || current.parentElement !== container) {
    const el = document.createElement('div');
    el.className = className;
    el.setAttribute('aria-hidden', 'true');
    container.appendChild(el);
    return el;
  }
  return current;
}

function hide(el: HTMLElement | null): void {
  if (el) el.style.display = 'none';
}

/**
 * Position the cursor marker at `line`/`col`. `col` is the 0-based **byte**
 * column from Neovim; it is used only in "caret" mode. Positioned in the
 * container's content coordinates (relative to the padding box) so it scrolls
 * with the content. Call after each render and on each cursor ping.
 */
export function updateCursorMarker(
  container: HTMLElement,
  line: number,
  col: number | null,
  mode: CursorMarkerMode,
): void {
  // Section spotlight decorates block elements; clear it whenever we're not in
  // that mode so switching modes doesn't leave dimmed blocks behind.
  if (mode !== 'section') clearSection(container);

  if (mode === 'off') {
    hide(barEl);
    hide(caretEl);
    hide(blockEl);
    return;
  }
  if (mode === 'section') {
    hide(barEl);
    hide(caretEl);
    hide(blockEl);
    placeSection(container, line);
    return;
  }
  const hasCol = typeof col === 'number' && col >= 0;
  if (mode === 'caret' && hasCol && placeCaret(container, line, col)) {
    hide(barEl);
    hide(blockEl);
    return;
  }
  if (mode === 'block' && hasCol && placeBlock(container, line, col)) {
    hide(barEl);
    hide(caretEl);
    return;
  }
  // "line" mode, or the caret/block fallback (blank line / code block / no run).
  placeLineBar(container, line);
  hide(caretEl);
  hide(blockEl);
}

/**
 * The share of a block's rendered height that source `line` occupies, as
 * fractions (0..1) of the block's height. A block spanning N source lines is
 * cut into N equal slices; a single-line block (a heading, a one-line paragraph
 * that wraps over several visual lines) is covered completely. A line outside
 * the block (a blank line after it) maps to the zero-height slice at its bottom.
 */
export function lineSlice(target: ScrollTarget, line: number): { from: number; to: number } {
  if (line < target.startLine) return { from: 0, to: 0 };
  if (line > target.endLine) return { from: 1, to: 1 };
  const lines = target.endLine - target.startLine + 1;
  const i = line - target.startLine;
  return { from: i / lines, to: (i + 1) / lines };
}

/**
 * Vertical extent of source `line` in the container's content coordinates.
 *
 * Exact where the DOM can say where the line's text is: through the inline
 * source-position runs (source map on) or a code block's own line structure.
 * The range over the line's text yields one rect per visual line, so a source
 * line that wraps is covered over all its visual lines. Elsewhere the line gets
 * its slice of the smallest block containing it (see lineSlice). Null when the
 * line cannot be located at all (before the first block, no sourcepos).
 */
export function lineBand(
  container: HTMLElement,
  line: number,
): { top: number; height: number } | null {
  const contRect = container.getBoundingClientRect();
  const toContent = (y: number) => y - contRect.top + container.scrollTop;

  const exact = textLineBox(container, line);
  if (exact) return { top: toContent(exact.top), height: exact.bottom - exact.top };

  const target = pickScrollTarget(container, line);
  if (!target) return null;
  const rect = target.el.getBoundingClientRect();
  const slice = lineSlice(target, line);
  return {
    top: toContent(rect.top + slice.from * rect.height),
    height: (slice.to - slice.from) * rect.height,
  };
}

/** Viewport top/bottom of the text on source `line`, or null if not measurable. */
function textLineBox(container: HTMLElement, line: number): { top: number; bottom: number } | null {
  const index = buildPosIndex(container);
  const start = lineStartPosition(container, line, index);
  const end = lineEndPosition(container, line, index);
  if (!start || !end) return null;
  const range = document.createRange();
  if (typeof range.getClientRects !== 'function') return null;
  try {
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset);
  } catch {
    return null;
  }
  let top = Infinity;
  let bottom = -Infinity;
  for (const r of Array.from(range.getClientRects())) {
    if (r.height <= 0) continue;
    top = Math.min(top, r.top);
    bottom = Math.max(bottom, r.bottom);
  }
  return bottom > top ? { top, bottom } : null;
}

/**
 * Highlight the cursor's whole line across the full width of the preview. The
 * column never matters here: the band marks the line, the caret mode marks the
 * column.
 */
function placeLineBar(container: HTMLElement, line: number): void {
  const band = lineBand(container, line);
  if (!band) {
    hide(barEl);
    return;
  }
  barEl = ensureEl(barEl, container, 'mdview-cursor-bar');
  barEl.style.display = 'block';
  barEl.style.top = `${band.top}px`;
  barEl.style.height = `${band.height}px`;
}

/**
 * Pixel position of the Neovim cursor in the container's **content** coordinates
 * (so it scrolls with the document), derived from the inline source-position
 * runs. Null when no run covers the line (blank line, code block) or there is no
 * layout. Exported for overlays that need to point at the cursor (magnifier,
 * attention ping) — see render/overlays.
 */
export function caretContentPos(
  container: HTMLElement,
  line: number,
  col: number,
): { x: number; y: number; h: number; w: number } | null {
  const box = caretViewportBox(container, line, col);
  if (!box) return null;
  const contRect = container.getBoundingClientRect();
  return {
    x: box.left - contRect.left + container.scrollLeft,
    y: box.top - contRect.top + container.scrollTop,
    h: box.height,
    w: box.width,
  };
}

/** Viewport-space box of the character at `line`/`col` (width: that character's), or null. */
function caretViewportBox(
  container: HTMLElement,
  line: number,
  col: number,
): { left: number; top: number; height: number; width: number } | null {
  const runs = runsOnLine(container, line);
  if (runs.length === 0) return null;

  const byteCol = col + 1; // Neovim 0-based byte col -> comrak 1-based byte col

  // Prefer the run that contains the column (sc..ec+1, so the position just
  // after the last byte counts). Otherwise anchor to the nearest run on the line:
  // the last run starting at/before the column (caret at its end), else the first.
  let run = runs.find(r => byteCol >= r.sc && byteCol <= r.ec + 1);
  let byteInRun: number;
  if (run) {
    byteInRun = byteCol - run.sc;
  } else {
    const before = [...runs].reverse().find(r => r.sc <= byteCol);
    if (before) {
      run = before;
      byteInRun = before.ec + 1 - before.sc; // end of that run
    } else {
      run = runs[0];
      byteInRun = 0; // start of the first run on the line
    }
  }

  const text = run.el.textContent ?? '';
  const u16 = byteOffsetToUtf16(text, byteInRun);
  const pos = findTextPosition(run.el, u16);
  if (!pos) return null;

  return caretPixelBox(pos.node, pos.offset);
}

/**
 * Place the caret at the 0-based byte column `col` on `line`. Returns false when
 * no run covers the position (caller falls back to the line bar).
 */
function placeCaret(container: HTMLElement, line: number, col: number): boolean {
  const p = caretContentPos(container, line, col);
  if (!p) return false; // no run / no layout (jsdom) — nothing to place

  caretEl = ensureEl(caretEl, container, 'mdview-cursor-caret');
  caretEl.style.display = 'block';
  caretEl.style.left = `${p.x}px`;
  caretEl.style.top = `${p.y}px`;
  caretEl.style.height = `${p.h}px`;
  return true;
}

/**
 * Place the block marker over the character at the 0-based byte column `col` on
 * `line`: the box of that character (its own width, so a wide character or a tab
 * gets a wide block), or, past the end of the line's text, a block as wide as the
 * last character. Returns false when no run covers the position (caller falls
 * back to the line bar).
 */
function placeBlock(container: HTMLElement, line: number, col: number): boolean {
  const p = caretContentPos(container, line, col);
  if (!p) return false;

  blockEl = ensureEl(blockEl, container, 'mdview-cursor-block');
  blockEl.style.display = 'block';
  blockEl.style.left = `${p.x}px`;
  blockEl.style.top = `${p.y}px`;
  blockEl.style.height = `${p.h}px`;
  blockEl.style.width = `${p.w}px`;
  // Blinking is opt-in and never shown to someone who asked for less motion.
  const blink = blinkMs !== false && !prefersReducedMotion();
  blockEl.classList.toggle('mdview-cursor-blink', blink);
  if (blink) blockEl.style.setProperty('--mdview-blink-ms', `${blinkMs}ms`);
  else blockEl.style.removeProperty('--mdview-blink-ms');
  return true;
}

/** Start of the UTF-16 unit run that is the character ending at `end` (a surrogate pair is one). */
function charStartBefore(data: string, end: number): number {
  const low = data.charCodeAt(end - 1);
  const high = end >= 2 ? data.charCodeAt(end - 2) : 0;
  return low >= 0xdc00 && low <= 0xdfff && high >= 0xd800 && high <= 0xdbff ? end - 2 : end - 1;
}

/** End of the character starting at `start` (a surrogate pair is one). */
function charEndAfter(data: string, start: number): number {
  const high = data.charCodeAt(start);
  const low = start + 1 < data.length ? data.charCodeAt(start + 1) : 0;
  return high >= 0xd800 && high <= 0xdbff && low >= 0xdc00 && low <= 0xdfff ? start + 2 : start + 1;
}

/**
 * Pixel box of the character at `offset` within text `node` (`left` is the
 * caret position, `width` the character's). A *collapsed* Range's
 * getBoundingClientRect is unreliable (several engines return a degenerate rect
 * at the block's left edge), so measure a one-character box instead: the
 * character at `offset`, or at end-of-node the character before it (the box then
 * starts at its right edge and is as wide as it). Returns null when there is no
 * layout (jsdom) or the node is empty.
 */
function caretPixelBox(
  node: Text,
  offset: number,
): { left: number; top: number; height: number; width: number } | null {
  const range = document.createRange();
  if (typeof range.getBoundingClientRect !== 'function') return null;
  const len = node.data.length;
  if (offset < len) {
    range.setStart(node, offset);
    range.setEnd(node, charEndAfter(node.data, offset));
    const r = range.getBoundingClientRect();
    if (r.width || r.height) return { left: r.left, top: r.top, height: r.height, width: r.width };
  }
  if (offset > 0) {
    range.setStart(node, charStartBefore(node.data, offset));
    range.setEnd(node, offset);
    const r = range.getBoundingClientRect();
    if (r.width || r.height) return { left: r.right, top: r.top, height: r.height, width: r.width };
  }
  // Empty node / no measurable box — last resort, the collapsed position.
  range.setStart(node, offset);
  range.collapse(true);
  const r = range.getBoundingClientRect();
  if (r.width || r.height || r.left || r.top) {
    return { left: r.left, top: r.top, height: r.height, width: r.width };
  }
  return null;
}

// ---- section spotlight (cursor_marker = "section") -------------------------

const SECTION_DIM_CLASS = 'mdview-section-dim';
const SECTION_ACTIVE_CLASS = 'mdview-section-active';

/** Remove any section-spotlight decoration from the container's blocks. */
function clearSection(container: HTMLElement): void {
  container
    .querySelectorAll(`.${SECTION_DIM_CLASS}, .${SECTION_ACTIVE_CLASS}`)
    .forEach(el => el.classList.remove(SECTION_DIM_CLASS, SECTION_ACTIVE_CLASS));
}

/**
 * Highlight the document section the cursor is in and dim the rest. The section
 * runs from the governing heading (the last heading at/before the cursor line)
 * to just before the next heading of the same or higher rank; content before the
 * first heading is treated as its own section. With no headings at all nothing
 * is dimmed (there are no sections to distinguish).
 */
function placeSection(container: HTMLElement, line: number): void {
  const blocks = topLevelBlocks(container);
  clearSection(container);
  const range = sectionRange(blocks, line);
  if (!range) return; // no blocks / no headings -> nothing to spotlight

  blocks.forEach((b, i) => {
    b.el.classList.add(
      i >= range.start && i <= range.end ? SECTION_ACTIVE_CLASS : SECTION_DIM_CLASS,
    );
  });
}

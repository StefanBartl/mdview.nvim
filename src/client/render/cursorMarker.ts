// src/client/render/cursorMarker.ts
//
// Shows where the Neovim cursor is, in the preview.
//
//  * "line"  (Stage A): a small blinking bar in the left gutter at the cursor's
//    line, positioned with the same sourcepos block + in-block interpolation as
//    the scroll sync — line-accurate even inside multi-line blocks, but it marks
//    the line, not the column.
//
//  * "caret" (Stage C): a caret at the exact cursor character. The WASM renderer
//    wraps inline text/code runs in `<span data-sp="sl:sc:el:ec">` (byte columns,
//    matching Neovim's byte-based cursor column). We find the run containing the
//    cursor, convert the byte offset into it to a UTF-16 offset, and place a DOM
//    Range there to read the pixel position. Falls back to the line bar on blank
//    lines, inside code blocks, or wherever no run covers the column.
//
// See docs/Roadmap/KONZEPT_links_und_cursor.md.

import { pickScrollTarget, fractionInBlock } from './scrollSync';
import { topLevelBlocks, sectionRange } from './docModel';

export type CursorMarkerMode = 'off' | 'line' | 'caret' | 'section';

export function parseCursorMarkerMode(param: string | null | undefined): CursorMarkerMode {
  if (param === 'off') return 'off';
  if (param === 'caret') return 'caret';
  if (param === 'section') return 'section';
  return 'line';
}

let barEl: HTMLElement | null = null;
let caretEl: HTMLElement | null = null;

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
    return;
  }
  if (mode === 'section') {
    hide(barEl);
    hide(caretEl);
    placeSection(container, line);
    return;
  }
  if (mode === 'caret' && typeof col === 'number' && col >= 0 && placeCaret(container, line, col)) {
    hide(barEl);
    return;
  }
  // "line" mode, or the caret fallback (blank line / code block / no run).
  placeLineBar(container, line);
  hide(caretEl);
}

function placeLineBar(container: HTMLElement, line: number): void {
  const target = pickScrollTarget(container, line);
  if (!target) {
    hide(barEl);
    return;
  }
  const rect = target.el.getBoundingClientRect();
  const contRect = container.getBoundingClientRect();
  const yInContent =
    rect.top - contRect.top + container.scrollTop + fractionInBlock(target, line) * rect.height;

  barEl = ensureEl(barEl, container, 'mdview-cursor-bar');
  barEl.style.display = 'block';
  barEl.style.top = `${yInContent}px`;
}

interface SpanRange {
  el: HTMLElement;
  sc: number; // start byte column (1-based)
  ec: number; // end byte column (1-based, inclusive of the last byte)
}

/** Parse the `data-sp="sl:sc:el:ec"` runs on `line` (single-line inline runs). */
function runsOnLine(container: HTMLElement, line: number): SpanRange[] {
  const out: SpanRange[] = [];
  container.querySelectorAll<HTMLElement>('span[data-sp]').forEach((el) => {
    const sp = el.getAttribute('data-sp');
    if (!sp) return;
    const p = sp.split(':');
    if (p.length !== 4) return;
    const sl = Number(p[0]);
    const sc = Number(p[1]);
    const el2 = Number(p[2]);
    const ec = Number(p[3]);
    if (sl !== line || el2 !== line) return; // only single-line runs
    if (!Number.isFinite(sc) || !Number.isFinite(ec)) return;
    out.push({ el, sc, ec });
  });
  out.sort((a, b) => a.sc - b.sc);
  return out;
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
): { x: number; y: number; h: number } | null {
  const box = caretViewportBox(container, line, col);
  if (!box) return null;
  const contRect = container.getBoundingClientRect();
  return {
    x: box.left - contRect.left + container.scrollLeft,
    y: box.top - contRect.top + container.scrollTop,
    h: box.height,
  };
}

/** Viewport-space caret box for `line`/`col`, or null. */
function caretViewportBox(
  container: HTMLElement,
  line: number,
  col: number,
): { left: number; top: number; height: number } | null {
  const runs = runsOnLine(container, line);
  if (runs.length === 0) return null;

  const byteCol = col + 1; // Neovim 0-based byte col -> comrak 1-based byte col

  // Prefer the run that contains the column (sc..ec+1, so the position just
  // after the last byte counts). Otherwise anchor to the nearest run on the line:
  // the last run starting at/before the column (caret at its end), else the first.
  let run = runs.find((r) => byteCol >= r.sc && byteCol <= r.ec + 1);
  let byteInRun: number;
  if (run) {
    byteInRun = byteCol - run.sc;
  } else {
    const before = [...runs].reverse().find((r) => r.sc <= byteCol);
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
 * Pixel box of the caret at `offset` within text `node`. A *collapsed* Range's
 * getBoundingClientRect is unreliable (several engines return a degenerate rect
 * at the block's left edge), so measure a one-character box instead: the left
 * edge of the character at `offset`, or the right edge of the character before
 * it at end-of-node. Returns null when there is no layout (jsdom) or the node is
 * empty.
 */
function caretPixelBox(
  node: Text,
  offset: number,
): { left: number; top: number; height: number } | null {
  const range = document.createRange();
  if (typeof range.getBoundingClientRect !== 'function') return null;
  const len = node.data.length;
  if (offset < len) {
    range.setStart(node, offset);
    range.setEnd(node, offset + 1);
    const r = range.getBoundingClientRect();
    if (r.width || r.height) return { left: r.left, top: r.top, height: r.height };
  }
  if (offset > 0) {
    range.setStart(node, offset - 1);
    range.setEnd(node, offset);
    const r = range.getBoundingClientRect();
    if (r.width || r.height) return { left: r.right, top: r.top, height: r.height };
  }
  // Empty node / no measurable box — last resort, the collapsed position.
  range.setStart(node, offset);
  range.collapse(true);
  const r = range.getBoundingClientRect();
  if (r.width || r.height || r.left || r.top) return { left: r.left, top: r.top, height: r.height };
  return null;
}

/** UTF-8 byte length of a single code point. */
function utf8Len(cp: number): number {
  if (cp <= 0x7f) return 1;
  if (cp <= 0x7ff) return 2;
  if (cp <= 0xffff) return 3;
  return 4;
}

/**
 * Convert a UTF-8 byte offset into `s` to a UTF-16 code-unit offset (what DOM
 * Range uses). Stops at the code-point boundary at/after the byte offset, and
 * clamps to the string length.
 */
function byteOffsetToUtf16(s: string, byteOffset: number): number {
  if (byteOffset <= 0) return 0;
  let bytes = 0;
  let u16 = 0;
  for (const ch of s) {
    if (bytes >= byteOffset) return u16;
    bytes += utf8Len(ch.codePointAt(0) ?? 0);
    u16 += ch.length;
  }
  return u16; // offset at/after the end
}

/** Find the descendant text node + local offset for a UTF-16 offset within `el`. */
function findTextPosition(el: HTMLElement, u16Offset: number): { node: Text; offset: number } | null {
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  let acc = 0;
  let last: Text | null = null;
  let node = walker.nextNode() as Text | null;
  while (node) {
    const len = node.data.length;
    if (u16Offset <= acc + len) {
      return { node, offset: Math.max(0, u16Offset - acc) };
    }
    acc += len;
    last = node;
    node = walker.nextNode() as Text | null;
  }
  if (last) return { node: last, offset: last.data.length };
  return null;
}

// ---- section spotlight (cursor_marker = "section") -------------------------

const SECTION_DIM_CLASS = 'mdview-section-dim';
const SECTION_ACTIVE_CLASS = 'mdview-section-active';

/** Remove any section-spotlight decoration from the container's blocks. */
function clearSection(container: HTMLElement): void {
  container
    .querySelectorAll(`.${SECTION_DIM_CLASS}, .${SECTION_ACTIVE_CLASS}`)
    .forEach((el) => el.classList.remove(SECTION_DIM_CLASS, SECTION_ACTIVE_CLASS));
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

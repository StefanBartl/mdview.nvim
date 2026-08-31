// src/client/render/selectionMarker.ts
//
// Draws the Neovim visual selection in the preview: what is selected with
// v / V / CTRL-V in the buffer appears highlighted in the browser, live.
//
// The point is showing a document to other people — a lecture, a screen share,
// a walkthrough. Pointing at something in Neovim is invisible to whoever is
// watching the browser tab; selecting it says "this part, here" in the window
// they are actually looking at.
//
// Drawn as absolutely-positioned rectangles over the document, NOT by wrapping
// the selected text in markup: a source selection routinely crosses element
// boundaries (half a paragraph into a list, a heading plus the code block under
// it), which no single wrapper can express, and mutating the rendered DOM would
// fight with every re-render. Rectangles come from a DOM Range's own client
// rects, so wrapped lines, tables and inline code all measure correctly.
//
// Coordinates in, from Neovim: 1-based lines, 1-based **byte** columns, `ec`
// addressing the first byte of the last selected character (see
// bindings/autocmds/selection_sync.lua).

import {
  buildPosIndex,
  positionAt,
  lineStartPosition,
  lineEndPosition,
  type TextPos,
} from './sourcePos';

export interface SourceSelection {
  mode: 'char' | 'line' | 'block';
  sl: number; // start line, 1-based
  sc: number; // start byte column, 1-based
  el: number; // end line, 1-based
  ec: number; // end byte column, 1-based, inclusive
}

const LAYER_CLASS = 'mdview-selection-layer';
const RECT_CLASS = 'mdview-selection-rect';

/**
 * A selection can legitimately produce many rectangles (one per visual line);
 * a document-wide `ggVG` on a long file should still not build thousands of
 * elements. Past this the highlight is drawn as far as the cap allows.
 */
const MAX_RECTS = 600;

/**
 * Validate a `selection` control payload. Returns null for "no selection"
 * (`false`/absent, what Neovim sends on leaving visual mode) and for anything
 * malformed — a bad payload must clear the highlight, never draw a wrong one.
 */
export function parseSelection(value: unknown): SourceSelection | null {
  if (!value || typeof value !== 'object') return null;
  const v = value as Record<string, unknown>;
  const mode = v.mode;
  if (mode !== 'char' && mode !== 'line' && mode !== 'block') return null;
  const nums = ['sl', 'sc', 'el', 'ec'].map(k => Number(v[k]));
  if (nums.some(n => !Number.isFinite(n) || n < 1)) return null;
  const [sl, sc, el, ec] = nums;
  if (el < sl) return null;
  return { mode, sl, sc, el, ec };
}

function ensureLayer(container: HTMLElement): HTMLElement {
  let layer = container.querySelector<HTMLElement>(`:scope > .${LAYER_CLASS}`);
  if (!layer) {
    layer = document.createElement('div');
    layer.className = LAYER_CLASS;
    layer.setAttribute('aria-hidden', 'true');
    container.appendChild(layer);
  }
  return layer;
}

/** Remove the selection highlight, if one is drawn. */
export function clearSelection(container: HTMLElement): void {
  container.querySelector<HTMLElement>(`:scope > .${LAYER_CLASS}`)?.remove();
}

/** Build a Range between two DOM positions; null when the pair is not orderable. */
function rangeBetween(start: TextPos, end: TextPos): Range | null {
  try {
    const range = document.createRange();
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset);
    return range;
  } catch {
    return null; // end before start across a re-render, detached nodes, …
  }
}

/**
 * The DOM Ranges covering `sel`: one per line for the two modes that address
 * lines individually, one Range spanning the whole thing for charwise.
 *
 * Linewise gets a Range per line rather than one long one on purpose. A single
 * Range's intermediate lines report the full width of their block box, so a
 * three-line selection would draw two text-wide bars around one full-width one
 * — technically what a browser selection looks like, and visibly inconsistent.
 * Per line, every bar hugs its own text.
 *
 * Charwise really does run through the line ends, so there one Range is both
 * simpler and more truthful.
 */
function rangesFor(container: HTMLElement, sel: SourceSelection): Range[] {
  // One scan of the document, then every line is a map lookup — a `ggVG` over
  // a long file would otherwise re-scan it once per line.
  const index = buildPosIndex(container);

  if (sel.mode === 'block' || sel.mode === 'line') {
    const out: Range[] = [];
    const lastLine = Math.min(sel.el, sel.sl + MAX_RECTS);
    for (let line = sel.sl; line <= lastLine; line++) {
      const start =
        sel.mode === 'line'
          ? lineStartPosition(container, line, index)
          : positionAt(container, line, sel.sc, 'before', index);
      const end =
        sel.mode === 'line'
          ? lineEndPosition(container, line, index)
          : positionAt(container, line, sel.ec, 'after', index);
      if (!start || !end) continue; // a blank line, or one no block covers
      const range = rangeBetween(start, end);
      if (range) out.push(range);
    }
    return out;
  }

  const start = positionAt(container, sel.sl, sel.sc, 'before', index);
  const end = positionAt(container, sel.el, sel.ec, 'after', index);
  if (!start || !end) return [];
  const range = rangeBetween(start, end);
  return range ? [range] : [];
}

interface Box {
  left: number;
  top: number;
  width: number;
  height: number;
}

/**
 * Merge rectangles that sit on the same visual line into one span. A Range over
 * nested inline elements reports a rect per inline box; drawn as separate
 * translucent divs they overlap and read as uneven banding.
 */
function mergeByLine(boxes: Box[]): Box[] {
  const out: Box[] = [];
  for (const box of boxes) {
    const row = out.find(
      b => Math.abs(b.top - box.top) <= 1 && Math.abs(b.height - box.height) <= 2,
    );
    if (!row) {
      out.push({ ...box });
      continue;
    }
    const right = Math.max(row.left + row.width, box.left + box.width);
    row.left = Math.min(row.left, box.left);
    row.width = right - row.left;
  }
  return out;
}

/** Measure `sel` against the current layout, in the container's content coordinates. */
function boxesFor(container: HTMLElement, sel: SourceSelection): Box[] {
  const ranges = rangesFor(container, sel);
  if (ranges.length === 0) return [];

  const contRect = container.getBoundingClientRect();
  const boxes: Box[] = [];
  for (const range of ranges) {
    if (typeof range.getClientRects !== 'function') return []; // no layout (jsdom)
    for (const rect of Array.from(range.getClientRects())) {
      if (rect.width <= 0 && rect.height <= 0) continue;
      boxes.push({
        left: rect.left - contRect.left + container.scrollLeft,
        top: rect.top - contRect.top + container.scrollTop,
        width: rect.width,
        height: rect.height,
      });
      if (boxes.length >= MAX_RECTS) break;
    }
    if (boxes.length >= MAX_RECTS) break;
  }
  return boxes;
}

/** What is currently highlighted, so a layout change can be re-measured. */
let current: { container: HTMLElement; sel: SourceSelection } | null = null;
let pendingFrame = 0;
let observer: ResizeObserver | null = null;

/**
 * Re-measure whenever the container's box changes.
 *
 * Rectangles are pixel positions, so anything that reflows the document
 * invalidates them: the window resizing, `:MDView zoom`, a web font arriving —
 * and, most sharply, the theme stylesheet, which is imported lazily and can
 * land *after* the first selection does. Measured against that half-styled
 * layout, a selection produces nonsense boxes that then sit there. Observing
 * the container turns every one of those into a self-correction.
 */
function observe(container: HTMLElement): void {
  if (typeof ResizeObserver === 'undefined') return; // jsdom, older engines
  if (!observer) observer = new ResizeObserver(() => scheduleDraw());
  observer.disconnect();
  observer.observe(container);
}

function scheduleDraw(): void {
  if (pendingFrame) return;
  if (typeof requestAnimationFrame !== 'function') {
    draw();
    return;
  }
  pendingFrame = requestAnimationFrame(() => {
    pendingFrame = 0;
    draw();
  });
}

/**
 * Measure and paint the current selection. Clearing happens here, right before
 * the new rectangles go in, so a selection being dragged doesn't flicker
 * between an empty frame and a drawn one.
 *
 * Never throws: a selection that can't be resolved (a stale line number, a code
 * block a client highlighter rebuilt, a document that has since changed) draws
 * nothing rather than breaking the preview.
 */
function draw(): void {
  if (!current) return;
  const { container, sel } = current;
  let boxes: Box[] = [];
  try {
    boxes = boxesFor(container, sel);
  } catch {
    boxes = [];
  }
  clearSelection(container);
  if (boxes.length === 0) return;

  const layer = ensureLayer(container);
  for (const box of mergeByLine(boxes)) {
    const el = document.createElement('div');
    el.className = RECT_CLASS;
    el.style.left = `${box.left}px`;
    el.style.top = `${box.top}px`;
    el.style.width = `${box.width}px`;
    el.style.height = `${box.height}px`;
    layer.appendChild(el);
  }
}

/**
 * Draw `sel` over `container`, replacing any previous highlight. Pass null to
 * clear it. Call after every render too — the render replaces the container's
 * innerHTML, which takes the layer with it.
 *
 * The painting itself happens on the next animation frame, so a fast drag
 * measures once per frame instead of once per message.
 */
export function updateSelection(container: HTMLElement, sel: SourceSelection | null): void {
  if (!sel) {
    current = null;
    observer?.disconnect();
    clearSelection(container);
    return;
  }
  current = { container, sel };
  observe(container);
  scheduleDraw();
}

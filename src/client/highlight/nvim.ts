// src/client/highlight/nvim.ts
//
// Paint fenced code blocks with Neovim's own colors, instead of guessing the
// language again in the browser. The spans arrive from the Lua side (see
// lua/mdview/core/fence_spans.lua) over the /spans channel: per block, per
// content row, byte columns with a resolved #rrggbb — read out of the
// highlighting color_my_ascii.nvim actually applied to the buffer.
//
// The result is that the preview and the buffer next to it agree, by
// construction rather than by coincidence: same colorscheme, same groups, and a
// theme change in Neovim reaches the browser on the next push.
//
// Blocks Neovim has no spans for are NOT left blank — they are handed to
// highlight.js, which still knows ~190 languages against color_my_ascii's 31
// fence tags. So this is an addition to the JavaScript highlighter, never a
// replacement that loses coverage.

import { buildPosIndex, byteOffsetToUtf16 } from '../render/sourcePos';

/** One highlighted run inside a content row: byte column, byte length, style. */
interface WireSpan {
  c: number; // 1-based byte column within the row
  n: number; // byte length
  f?: string; // foreground "#rrggbb"
  g?: string; // background "#rrggbb"
  b?: boolean; // bold
  i?: boolean; // italic
  u?: boolean; // underline
  s?: boolean; // strikethrough
}

interface WireBlock {
  line: number; // 1-based source line of the block's FIRST CONTENT line
  rows: WireSpan[][];
}

interface WirePayload {
  v: number;
  blocks: WireBlock[];
}

/** The wire format this client understands; anything else is ignored. */
const SUPPORTED_VERSION = 1;

/** Marks a `<pre>` painted from Neovim, so highlight.js skips it. */
const PAINTED_ATTR = 'data-nvim-hl';

let payload: WirePayload | null = null;

/**
 * Record the latest fence highlighting from Neovim. `null` (the Lua side has
 * nothing to paint, or the payload is malformed or of an unknown version) drops
 * every block back to highlight.js on the next pass.
 */
export function setSpans(value: unknown): void {
  payload = parsePayload(value);
}

/** Whether any spans are currently known — used to decide if a repaint is worth it. */
export function hasSpans(): boolean {
  return payload !== null;
}

function parsePayload(value: unknown): WirePayload | null {
  if (!value || typeof value !== 'object') return null;
  const v = value as Record<string, unknown>;
  if (v.v !== SUPPORTED_VERSION || !Array.isArray(v.blocks)) return null;
  const blocks: WireBlock[] = [];
  for (const raw of v.blocks) {
    if (!raw || typeof raw !== 'object') continue;
    const b = raw as Record<string, unknown>;
    const line = Number(b.line);
    if (!Number.isFinite(line) || line < 1 || !Array.isArray(b.rows)) continue;
    const rows: WireSpan[][] = b.rows.map(row => (Array.isArray(row) ? (row as WireSpan[]) : []));
    blocks.push({ line, rows });
  }
  return blocks.length > 0 ? { v: SUPPORTED_VERSION, blocks } : null;
}

/** The CSS declarations for one span, or '' when it carries no style at all. */
function styleFor(span: WireSpan): string {
  const decls: string[] = [];
  if (typeof span.f === 'string') decls.push(`color:${span.f}`);
  if (typeof span.g === 'string') decls.push(`background-color:${span.g}`);
  if (span.b) decls.push('font-weight:bold');
  if (span.i) decls.push('font-style:italic');
  if (span.u && span.s) decls.push('text-decoration:underline line-through');
  else if (span.u) decls.push('text-decoration:underline');
  else if (span.s) decls.push('text-decoration:line-through');
  return decls.join(';');
}

/**
 * Rebuild one row as text and styled spans.
 *
 * Columns are byte columns from Neovim; the row is a JavaScript string, so each
 * boundary is converted through the same UTF-8→UTF-16 mapping the cursor caret
 * uses. Gaps between spans stay unstyled — an unpainted stretch inside a
 * painted block is genuinely unpainted, not an omission to guess at.
 */
function paintRow(row: string, spans: WireSpan[]): DocumentFragment {
  const frag = document.createDocumentFragment();
  let cursor = 0; // UTF-16 offset already emitted

  const ordered = [...spans].sort((a, b) => a.c - b.c);
  for (const span of ordered) {
    const start = byteOffsetToUtf16(row, span.c - 1);
    const end = byteOffsetToUtf16(row, span.c - 1 + span.n);
    if (!(end > start) || start < cursor) continue; // malformed or overlapping
    if (start > cursor) frag.appendChild(document.createTextNode(row.slice(cursor, start)));
    const style = styleFor(span);
    if (style) {
      const el = document.createElement('span');
      el.setAttribute('style', style);
      el.textContent = row.slice(start, end);
      frag.appendChild(el);
    } else {
      frag.appendChild(document.createTextNode(row.slice(start, end)));
    }
    cursor = end;
  }
  if (cursor < row.length) frag.appendChild(document.createTextNode(row.slice(cursor)));
  return frag;
}

/**
 * Paint every code block `root` has spans for, and hand the rest to
 * highlight.js.
 *
 * Blocks are matched by the source line of their first content line — the one
 * thing both sides can name without knowing whether the block was fenced or
 * indented (the client derives it in sourcePos.ts, Neovim sends
 * `block.content_start + 1`).
 *
 * The DOM is rebuilt with createElement/createTextNode rather than innerHTML:
 * the code's text is document content, and it must never be able to become
 * markup on its way through the highlighter.
 */
export async function highlightAll(root: HTMLElement): Promise<void> {
  const index = buildPosIndex(root);
  const byLine = new Map<number, WireBlock>();
  for (const block of payload?.blocks ?? []) byLine.set(block.line, block);

  for (const block of index.blocks) {
    const spans = byLine.get(block.firstLine);
    const code = block.el.querySelector('code') ?? block.el;
    if (!spans) {
      code.removeAttribute(PAINTED_ATTR);
      continue;
    }
    // The rows Neovim sent describe the buffer's lines; if the rendered block
    // has a different number of them the two are out of step (an edit landed
    // between the content push and the spans push) — leave it to highlight.js
    // for this frame rather than painting the wrong columns.
    if (spans.rows.length !== block.lines.length) continue;

    const frag = document.createDocumentFragment();
    block.lines.forEach((line, i) => {
      if (i > 0) frag.appendChild(document.createTextNode('\n'));
      frag.appendChild(paintRow(line, spans.rows[i] ?? []));
    });
    // comrak ends a code block with a newline and highlight.js keeps it;
    // painting must not quietly change the text, or a painted block would sit
    // a hair differently from an unpainted one on the same page.
    if ((code.textContent ?? '').endsWith('\n')) frag.appendChild(document.createTextNode('\n'));
    code.textContent = '';
    code.appendChild(frag);
    code.setAttribute(PAINTED_ATTR, '');
  }

  // Everything Neovim did not paint still deserves colors — highlight.js knows
  // far more languages than color_my_ascii's fence map covers.
  const { highlightAll: hljsAll } = await import('./hljs');
  hljsAll(root, `pre code:not([${PAINTED_ATTR}])`);
}

// src/client/render/sourcePos.ts
//
// Source position -> DOM position. The WASM renderer wraps inline Text/Code
// runs in `<span data-sp="sl:sc:el:ec">` (1-based **byte** columns, matching
// Neovim's byte-based columns) and puts `data-sourcepos` on block elements.
// This module turns a (line, byte column) pair from Neovim into a concrete
// `{ text node, offset }` the DOM can measure or build a Range from.
//
// Extracted from cursorMarker.ts so the cursor caret and the visual-selection
// mirror resolve positions through one implementation instead of two: they
// disagree about what to *draw*, never about where a source column IS.
//
// Code blocks need their own path. `annotate_source_positions` deliberately
// leaves fenced/indented code alone (a client highlighter re-tokenizes those
// and would strip inner spans), so a `<pre>` has no inline runs — but its
// `data-sourcepos` plus its own line structure locate a column just as well.

export interface SpanRange {
  el: HTMLElement;
  sc: number; // start byte column (1-based)
  ec: number; // end byte column (1-based, inclusive of the last byte)
}

/** DOM text position: a text node plus a UTF-16 offset inside it. */
export interface TextPos {
  node: Text;
  offset: number;
}

/** A code block's rendered lines, and the source line its first one sits on. */
interface CodeBlock {
  el: HTMLElement;
  lines: string[];
  firstLine: number;
}

/**
 * The document's source positions, gathered once: inline runs keyed by line,
 * plus every `<pre>` that still carries a source position.
 *
 * Resolving one position scans the document; resolving several hundred (a
 * linewise selection over a long stretch) would scan it several hundred times.
 * Callers that ask about more than one line build this first and pass it in.
 * It is valid until the next render replaces the DOM — never store it.
 */
export interface PosIndex {
  runs: Map<number, SpanRange[]>;
  blocks: CodeBlock[];
}

/** Collect every inline run and code block under `container`. */
export function buildPosIndex(container: HTMLElement): PosIndex {
  const runs = new Map<number, SpanRange[]>();
  container.querySelectorAll<HTMLElement>('span[data-sp]').forEach(el => {
    const sp = el.getAttribute('data-sp');
    if (!sp) return;
    const p = sp.split(':');
    if (p.length !== 4) return;
    const sl = Number(p[0]);
    const sc = Number(p[1]);
    const el2 = Number(p[2]);
    const ec = Number(p[3]);
    if (sl !== el2) return; // only single-line runs
    if (!Number.isFinite(sl) || !Number.isFinite(sc) || !Number.isFinite(ec)) return;
    const bucket = runs.get(sl);
    if (bucket) bucket.push({ el, sc, ec });
    else runs.set(sl, [{ el, sc, ec }]);
  });
  for (const bucket of runs.values()) bucket.sort((a, b) => a.sc - b.sc);

  const blocks: CodeBlock[] = [];
  container.querySelectorAll<HTMLElement>('pre[data-sourcepos]').forEach(pre => {
    const range = blockLines(pre);
    if (!range) return;
    const lines = (pre.textContent ?? '').split('\n');
    if (lines.length > 1 && lines[lines.length - 1] === '') lines.pop(); // trailing newline
    const spanned = range.end - range.start + 1;
    blocks.push({
      el: pre,
      lines,
      // A fenced block's sourcepos spans its delimiters, an indented one's does
      // not — told apart by the line count, since the rendered DOM no longer
      // has the backticks to look for.
      firstLine: spanned === lines.length ? range.start : range.start + 1,
    });
  });

  return { runs, blocks };
}

/** The `data-sp` runs on `line` (single-line inline runs), in column order. */
export function runsOnLine(container: HTMLElement, line: number, index?: PosIndex): SpanRange[] {
  return (index ?? buildPosIndex(container)).runs.get(line) ?? [];
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
 * clamps to the string length. A byte offset pointing INTO a multi-byte
 * character therefore yields the boundary after it — which is what an
 * inclusive end column needs.
 */
export function byteOffsetToUtf16(s: string, byteOffset: number): number {
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
export function findTextPosition(el: HTMLElement, u16Offset: number): TextPos | null {
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

/** Parse `data-sourcepos="sl:sc-el:ec"` into its start/end lines. */
function blockLines(el: Element): { start: number; end: number } | null {
  const sp = el.getAttribute('data-sourcepos');
  if (!sp) return null;
  const [startPart, endPart] = sp.split('-');
  const start = Number(startPart?.split(':')[0]);
  const end = Number(endPart?.split(':')[0]);
  if (!Number.isFinite(start) || !Number.isFinite(end)) return null;
  return { start, end };
}

/**
 * The code block containing source `line`, or null — including for a `<pre>` a
 * client highlighter replaced wholesale (Shiki rebuilds the element and drops
 * `data-sourcepos` with it), which the selection skips rather than guesses at.
 */
function codeBlockAt(container: HTMLElement, line: number, index?: PosIndex): CodeBlock | null {
  const blocks = (index ?? buildPosIndex(container)).blocks;
  for (const block of blocks) {
    const idx = line - block.firstLine;
    if (idx >= 0 && idx < block.lines.length) return block;
  }
  return null;
}

/** Where in a line's text a position sits: before its first byte, or after it. */
export type Bias = 'before' | 'after';

/**
 * DOM position for source `line` / 1-based byte column `col`.
 *
 * `bias` picks which side of the addressed character: "before" for a start
 * column, "after" for an inclusive end column (which then covers the whole
 * character, multi-byte included).
 *
 * Columns outside the line's content clamp to its nearest edge, so a selection
 * whose end column runs past the end of a short line still ends there instead
 * of vanishing.
 */
export function positionAt(
  container: HTMLElement,
  line: number,
  col: number,
  bias: Bias,
  index?: PosIndex,
): TextPos | null {
  const runs = runsOnLine(container, line, index);
  if (runs.length > 0) {
    let run = runs.find(r => col >= r.sc && col <= r.ec + 1);
    if (!run) {
      const before = [...runs].reverse().find(r => r.sc <= col);
      // Past the last run -> its end; before the first -> its start.
      run = before ?? runs[0];
      const text = run.el.textContent ?? '';
      return findTextPosition(run.el, before ? text.length : 0);
    }
    const text = run.el.textContent ?? '';
    const byteInRun = col - run.sc + (bias === 'after' ? 1 : 0);
    return findTextPosition(run.el, byteOffsetToUtf16(text, byteInRun));
  }

  const block = codeBlockAt(container, line, index);
  if (!block) return null;
  const idx = line - block.firstLine;

  let offset = 0;
  for (let i = 0; i < idx; i++) offset += block.lines[i].length + 1; // + the newline
  const lineText = block.lines[idx];
  offset += byteOffsetToUtf16(lineText, col - 1 + (bias === 'after' ? 1 : 0));
  return findTextPosition(block.el, offset);
}

/** DOM position at the very start of source `line`, or null if it has none. */
export function lineStartPosition(
  container: HTMLElement,
  line: number,
  index?: PosIndex,
): TextPos | null {
  const runs = runsOnLine(container, line, index);
  if (runs.length > 0) return findTextPosition(runs[0].el, 0);
  return positionAt(container, line, 1, 'before', index);
}

/** DOM position just past the last character of source `line`, or null. */
export function lineEndPosition(
  container: HTMLElement,
  line: number,
  index?: PosIndex,
): TextPos | null {
  const runs = runsOnLine(container, line, index);
  if (runs.length > 0) {
    const last = runs[runs.length - 1];
    return findTextPosition(last.el, (last.el.textContent ?? '').length);
  }
  const block = codeBlockAt(container, line, index);
  if (!block) return null;
  const idx = line - block.firstLine;
  return positionAt(container, line, block.lines[idx].length + 1, 'before', index);
}

// src/client/render/cursorParagraph.ts
//
// Cursor paragraph highlight (browser.cursor_paragraph, :MDView paragraph): the
// top-level block the Neovim cursor is in gets a tinted background, so whoever
// looks at the preview sees which block the editor is working on. Independent of
// the cursor marker (line band / caret / section spotlight), which can be shown
// at the same time.
//
// "Paragraph" means a top-level block of the rendered document: a paragraph (the
// text up to the next blank line), and a list, a table, a code block, a block
// quote or a heading, each as one block. The mapping uses the renderer's
// data-sourcepos, so a fenced code block with blank lines inside stays one block,
// and the frontmatter table (which carries the sourcepos of the whole
// frontmatter, see replace_front_matter in the WASM renderer) is one block too. A
// cursor on a blank line between two blocks highlights nothing.

import { topLevelBlocks, type BlockPos } from './docModel';

export const PARAGRAPH_CLASS = 'mdview-cursor-paragraph';

/** CSS custom property that carries the color from Neovim's highlight group. */
export const PARAGRAPH_BG_VAR = '--cursor-paragraph-bg';

/** `?para=1` switches the highlight on; anything else leaves it off. */
export function parseCursorParagraph(param: string | null | undefined): boolean {
  return param === '1';
}

/**
 * A `#rrggbb` color from `?parabg=` / the control message, or null. The query
 * parameter carries it without the `#` (a `#` would start the URL fragment), so
 * both forms are accepted.
 */
export function parseParagraphColor(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const hex = value.startsWith('#') ? value.slice(1) : value;
  return /^[0-9a-fA-F]{6}$/.test(hex) ? `#${hex.toLowerCase()}` : null;
}

// Source lines of the last document handed in, split once per document rather
// than once per cursor ping.
let splitSource: string | null = null;
let splitLines: readonly string[] = [];

function sourceLines(source: string): readonly string[] {
  if (source !== splitSource) {
    splitSource = source;
    splitLines = source.split(/\r?\n/);
  }
  return splitLines;
}

const isBlank = (text: string | undefined): boolean => text === undefined || /^\s*$/.test(text);

/**
 * Last source line holding text of `block`. comrak ends a block that swallows the
 * blank lines after it (a list, an indented code block) at column 0 of the LAST
 * of those blank lines; none of them belongs to the block. With the document's
 * `lines` the whole blank run is dropped; without them only the line comrak
 * ends on is.
 */
function lastTextLine(block: BlockPos, lines?: readonly string[]): number {
  if (block.endCol !== 0 || block.endLine <= block.startLine) return block.endLine;
  let end = block.endLine - 1;
  if (lines) while (end > block.startLine && isBlank(lines[end - 1])) end--;
  return end;
}

/**
 * The top-level block that contains source `line` (1-based), or null when the
 * line is blank between blocks, before the first or after the last block.
 * `lines` (the rendered document's source lines) lets a run of blank lines after
 * a list or an indented code block map to nothing, as any other blank line does.
 */
export function paragraphBlockAt(
  blocks: BlockPos[],
  line: number,
  lines?: readonly string[],
): BlockPos | null {
  for (const b of blocks) {
    if (b.startLine > line) return null; // blocks are in increasing line order
    if (line <= lastTextLine(b, lines)) return b;
  }
  return null;
}

/**
 * Highlight the block under the cursor `line`, or clear the highlight when
 * `enabled` is false or the line is in no block. Call after each render (the
 * class goes with the replaced DOM) and on each cursor ping. `source` is the
 * Markdown the DOM was rendered from (see paragraphBlockAt).
 */
export function updateCursorParagraph(
  container: HTMLElement,
  line: number,
  enabled: boolean,
  source?: string,
): void {
  const lines = source === undefined ? undefined : sourceLines(source);
  const target =
    enabled && line >= 1 ? paragraphBlockAt(topLevelBlocks(container), line, lines) : null;
  // Leave an unchanged highlight alone: a cursor ping per keystroke must not
  // restart the CSS transition.
  container.querySelectorAll(`.${PARAGRAPH_CLASS}`).forEach(el => {
    if (el !== target?.el) el.classList.remove(PARAGRAPH_CLASS);
  });
  target?.el.classList.add(PARAGRAPH_CLASS);
}

/** Set (or with null, drop back to the theme's own tint) the highlight color. */
export function applyParagraphColor(root: HTMLElement, color: string | null): void {
  if (color) root.style.setProperty(PARAGRAPH_BG_VAR, color);
  else root.style.removeProperty(PARAGRAPH_BG_VAR);
}

// src/client/render/docModel.ts
//
// Shared read model over the rendered document: the top-level blocks and their
// source lines, the heading outline, and which heading "governs" a given cursor
// line. Extracted so the cursor marker (section spotlight) and the overlays
// (floating TOC, …) derive structure from one place instead of duplicating the
// data-sourcepos parsing.

export interface BlockPos {
  el: HTMLElement;
  startLine: number;
  headingLevel: number | null; // 1..6 for H1..H6, else null
}

export interface HeadingInfo {
  el: HTMLElement;
  line: number;
  level: number;
  text: string;
  index: number; // position within the heading list
}

/** Top-level blocks of the container that carry data-sourcepos, in doc order. */
export function topLevelBlocks(container: HTMLElement): BlockPos[] {
  const out: BlockPos[] = [];
  for (const child of Array.from(container.children)) {
    if (!(child instanceof HTMLElement)) continue;
    const sp = child.getAttribute('data-sourcepos');
    if (!sp) continue;
    const startLine = Number(sp.split(':')[0]);
    if (!Number.isFinite(startLine)) continue;
    const m = /^H([1-6])$/.exec(child.tagName);
    out.push({ el: child, startLine, headingLevel: m ? Number(m[1]) : null });
  }
  return out;
}

/** The document's heading outline, in order. */
export function headings(container: HTMLElement): HeadingInfo[] {
  const out: HeadingInfo[] = [];
  for (const b of topLevelBlocks(container)) {
    if (b.headingLevel === null) continue;
    out.push({
      el: b.el,
      line: b.startLine,
      level: b.headingLevel,
      text: (b.el.textContent ?? '').trim(),
      index: out.length,
    });
  }
  return out;
}

/**
 * The heading that governs `line`: the last heading starting at or before it.
 * Null when the line sits above the first heading (or there are none).
 */
export function governingHeading(container: HTMLElement, line: number): HeadingInfo | null {
  let found: HeadingInfo | null = null;
  for (const h of headings(container)) {
    if (h.line > line) break;
    found = h;
  }
  return found;
}

/**
 * Inclusive block-index range of the section containing `line`: from the
 * governing heading to just before the next heading of the same or higher rank.
 * Content above the first heading is its own section. Null when the document has
 * no headings (nothing to delimit).
 */
export function sectionRange(blocks: BlockPos[], line: number): { start: number; end: number } | null {
  if (blocks.length === 0) return null;
  const firstHeadingIdx = blocks.findIndex((b) => b.headingLevel !== null);
  if (firstHeadingIdx === -1) return null;

  let headingIdx = -1;
  let headingLvl = 0;
  for (const [i, b] of blocks.entries()) {
    if (b.startLine > line) break; // blocks are in increasing line order
    if (b.headingLevel !== null) {
      headingIdx = i;
      headingLvl = b.headingLevel;
    }
  }

  if (headingIdx === -1) return { start: 0, end: firstHeadingIdx - 1 };

  let end = blocks.length - 1;
  for (let j = headingIdx + 1; j < blocks.length; j++) {
    const lvl = blocks[j].headingLevel;
    if (lvl !== null && lvl <= headingLvl) {
      end = j - 1;
      break;
    }
  }
  return { start: headingIdx, end };
}

/** Scroll `container` so `el` sits near the top of the viewport. */
export function scrollToBlock(container: HTMLElement, el: HTMLElement, offset = 8): void {
  const top = el.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop;
  container.scrollTo({ top: Math.max(0, top - offset), behavior: 'smooth' });
}

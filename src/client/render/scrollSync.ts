// src/client/render/scrollSync.ts
//
// Maps a Neovim cursor line to a precise vertical position in the rendered
// document using comrak's data-sourcepos="startLine:col-endLine:col" hints.
// sourcepos is per-block, so within a multi-line block (e.g. a paragraph) we
// interpolate by how far the cursor line is through the block's line span —
// giving line-accurate scrolling instead of block-granular jumps. The actual
// scrolling (which needs layout geometry) stays in main.ts; selection +
// interpolation live here so they're unit-testable in jsdom.

export interface ScrollTarget {
  el: HTMLElement;
  startLine: number;
  endLine: number;
}

function parseSourcepos(sp: string | null): { start: number; end: number } | null {
  if (!sp) return null;
  const m = sp.match(/^(\d+):\d+-(\d+):\d+/);
  if (!m) return null;
  const start = Number(m[1]);
  const end = Number(m[2]);
  if (!Number.isFinite(start) || !Number.isFinite(end)) return null;
  return { start, end };
}

/**
 * Choose the block for `line`: the smallest-span block that *contains* it
 * (start ≤ line ≤ end); if none contains it (e.g. the cursor is on a blank line
 * between blocks), the closest block starting at or before it; else null.
 */
export function pickScrollTarget(container: HTMLElement, line: number): ScrollTarget | null {
  const nodes = container.querySelectorAll<HTMLElement>('[data-sourcepos]');
  let containing: ScrollTarget | null = null;
  let containingSpan = Infinity;
  let before: ScrollTarget | null = null;
  let beforeStart = -1;

  nodes.forEach(el => {
    const pos = parseSourcepos(el.getAttribute('data-sourcepos'));
    if (!pos) return;
    if (pos.start <= line && line <= pos.end) {
      const span = pos.end - pos.start;
      if (span < containingSpan) {
        containingSpan = span;
        containing = { el, startLine: pos.start, endLine: pos.end };
      }
    }
    if (pos.start <= line && pos.start > beforeStart) {
      beforeStart = pos.start;
      before = { el, startLine: pos.start, endLine: pos.end };
    }
  });

  return containing ?? before;
}

/** Fraction (0..1) of `line`'s position through the target block's line span. */
export function fractionInBlock(target: ScrollTarget, line: number): number {
  const span = target.endLine - target.startLine;
  if (span <= 0) return 0;
  const f = (line - target.startLine) / span;
  return f < 0 ? 0 : f > 1 ? 1 : f;
}

/** Whether the container has any source-position hints to map against. */
export function hasSourcepos(container: HTMLElement): boolean {
  return container.querySelector('[data-sourcepos]') !== null;
}
